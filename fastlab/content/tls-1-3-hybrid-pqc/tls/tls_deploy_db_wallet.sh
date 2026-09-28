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
pdb_name_sql=${PDB_NAME//\'/\'\'}
pdb_guid=$(
    "$SQLPLUS" -s / as sysdba <<SQL
set heading off feedback off pagesize 0 verify off echo off
select guid from v\$containers where upper(name) = upper('$pdb_name_sql');
exit;
SQL
)
pdb_guid=$(printf '%s' "$pdb_guid" | tr -d '[:space:]')
if [[ ! $pdb_guid =~ ^[[:xdigit:]]{32}$ ]]; then
    tls_die "Could not resolve a single PDB GUID for PDB_NAME=$PDB_NAME."
fi
PDB_TLS_DIR="${PDB_TLS_DIR:-$WALLET_ROOT/$pdb_guid/tls}"
printf '%s\n' "Deploying the PDB server wallet to $PDB_TLS_DIR."

# Preserve any deployed wallet files before changing WALLET_ROOT, restarting the
# database, creating directories, or copying into ORACLE_BASE-derived paths.
tls_backup_directory "$TLS_DIR"
tls_backup_directory "$PDB_TLS_DIR"
tls_backup_directory "$ORA_TLS_DIR"
tls_backup_file "$TLS_DIR/ewallet.p12"
tls_backup_file "$TLS_DIR/cwallet.sso"
tls_backup_file "$PDB_TLS_DIR/ewallet.p12"
tls_backup_file "$PDB_TLS_DIR/cwallet.sso"
tls_backup_file "$ORA_TLS_DIR/ewallet.p12"
tls_backup_file "$ORA_TLS_DIR/cwallet.sso"

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


mkdir -p -- "$TLS_DIR" "$PDB_TLS_DIR" "$ORA_TLS_DIR" 2>/dev/null || tls_run_as_root mkdir -p -- "$TLS_DIR" "$PDB_TLS_DIR" "$ORA_TLS_DIR"
if ! cp -p -- "$DB_TLS_DIR/ewallet.p12" "$DB_TLS_DIR/cwallet.sso" "$TLS_DIR/" 2>/dev/null; then
    tls_run_as_root cp -p -- "$DB_TLS_DIR/ewallet.p12" "$DB_TLS_DIR/cwallet.sso" "$TLS_DIR/"
fi
if ! cp -p -- "$DB_TLS_DIR/ewallet.p12" "$DB_TLS_DIR/cwallet.sso" "$PDB_TLS_DIR/" 2>/dev/null; then
    tls_run_as_root cp -p -- "$DB_TLS_DIR/ewallet.p12" "$DB_TLS_DIR/cwallet.sso" "$PDB_TLS_DIR/"
fi
if ! cp -p -- "$DB_TLS_DIR/ewallet.p12" "$DB_TLS_DIR/cwallet.sso" "$ORA_TLS_DIR/" 2>/dev/null; then
    tls_run_as_root cp -p -- "$DB_TLS_DIR/ewallet.p12" "$DB_TLS_DIR/cwallet.sso" "$ORA_TLS_DIR/"
fi

if [[ -n ${TLS_ORACLE_OWNER:-} && ${TLS_ORACLE_OWNER} != "$(id -un)" ]]; then
    tls_chown_path "$TLS_DIR" "$TLS_ORACLE_OWNER"
    tls_chown_path "$PDB_TLS_DIR" "$TLS_ORACLE_OWNER"
    tls_chown_path "$ORA_TLS_DIR" "$TLS_ORACLE_OWNER"
fi

"$ORAPKI" wallet display -wallet "$TLS_DIR" -pwd "$TLS_PASSWORD" | tls_filter_orapki
