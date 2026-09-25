#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

tls_init
tls_require_password
ORAPKI=$(tls_require_oracle_bin orapki)
SQLPLUS=$(tls_require_oracle_bin sqlplus)
tls_require_file "$DB_TLS_DIR/ewallet.p12"

printf '%s\n' "Deploying the database wallet to $TLS_DIR and client wallet $ORA_TLS_DIR."
wallet_root_sql=${WALLET_ROOT//\'/\'\'}

if [[ ${TLS_SET_WALLET_ROOT:-YES} == YES ]]; then
    if [[ ${TLS_RESTART_DATABASE:-YES} == YES ]]; then
        "$SQLPLUS" -s / as sysdba <<SQL
alter system set wallet_root = '$wallet_root_sql' scope=spfile;
shutdown immediate;
startup;
show parameter wallet_root;
exit;
SQL
    else
        "$SQLPLUS" -s / as sysdba <<SQL
alter system set wallet_root = '$wallet_root_sql' scope=spfile;
show parameter wallet_root;
exit;
SQL
        tls_warn 'TLS_RESTART_DATABASE is not YES; restart the database before using WALLET_ROOT.'
    fi
fi

# Preserve any deployed wallet files before creating directories or copying
# into locations derived from WALLET_ROOT/ORACLE_BASE.
tls_backup_file "$TLS_DIR/ewallet.p12"
tls_backup_file "$TLS_DIR/cwallet.sso"
tls_backup_file "$ORA_TLS_DIR/ewallet.p12"
tls_backup_file "$ORA_TLS_DIR/cwallet.sso"

mkdir -p -- "$TLS_DIR" "$ORA_TLS_DIR" 2>/dev/null || tls_run_as_root mkdir -p -- "$TLS_DIR" "$ORA_TLS_DIR"
if ! cp -p -- "$DB_TLS_DIR/ewallet.p12" "$DB_TLS_DIR/cwallet.sso" "$TLS_DIR/" 2>/dev/null; then
    tls_run_as_root cp -p -- "$DB_TLS_DIR/ewallet.p12" "$DB_TLS_DIR/cwallet.sso" "$TLS_DIR/"
fi
if ! cp -p -- "$DB_TLS_DIR/ewallet.p12" "$DB_TLS_DIR/cwallet.sso" "$ORA_TLS_DIR/" 2>/dev/null; then
    tls_run_as_root cp -p -- "$DB_TLS_DIR/ewallet.p12" "$DB_TLS_DIR/cwallet.sso" "$ORA_TLS_DIR/"
fi

if [[ -n ${TLS_ORACLE_OWNER:-} && ${TLS_ORACLE_OWNER} != "$(id -un)" ]]; then
    tls_chown_path "$TLS_DIR" "$TLS_ORACLE_OWNER"
    tls_chown_path "$ORA_TLS_DIR" "$TLS_ORACLE_OWNER"
fi

"$ORAPKI" wallet display -wallet "$TLS_DIR" -pwd "$TLS_PASSWORD" | tls_filter_orapki
