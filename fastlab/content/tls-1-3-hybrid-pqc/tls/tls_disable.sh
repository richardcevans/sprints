#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

tls_init
tls_confirm_destructive "${1:-}"

SQLNET_FILE="$TNS_ADMIN/sqlnet.ora"
TNSNAMES_FILE="$TNS_ADMIN/tnsnames.ora"
LISTENER_FILE="$TNS_ADMIN/listener.ora"

for file in "$SQLNET_FILE" "$TNSNAMES_FILE" "$LISTENER_FILE"; do
    [[ -e $file ]] || continue
    tls_backup_file "$file"
done

if [[ -e $SQLNET_FILE ]]; then
    tls_edit_in_place "$SQLNET_FILE" -E '/^[[:space:]]*(SSL_CLIENT_AUTHENTICATION|TLS_VERSION|TLS_KEY_EXCHANGE_GROUPS)[[:space:]]*=.*/d'
fi
if [[ -e $TNSNAMES_FILE && ${TLS_REMOVE_TNS_ALIAS:-YES} == YES ]]; then
    # The generated lab alias is eight lines without a SECURITY clause. Keep the
    # original backup if a site uses a differently shaped tnsnames.ora entry.
    tls_edit_in_place "$TNSNAMES_FILE" -E "/^[[:space:]]*${TLS_TNS_ALIAS}[[:space:]]*=/,+8d"
fi
if [[ -e $LISTENER_FILE ]]; then
    tls_edit_in_place "$LISTENER_FILE" -E '/^[[:space:]]*(SSL_CLIENT_AUTHENTICATION|TLS_VERSION|TLS_KEY_EXCHANGE_GROUPS)[[:space:]]*=.*/d'
fi

LSNRCTL=$(tls_require_oracle_bin lsnrctl)
"$LSNRCTL" reload "${TLS_LISTENER_NAME}" 2>/dev/null || "$LSNRCTL" reload 2>/dev/null || true

if [[ ${TLS_REMOVE_WALLETS:-NO} == YES ]]; then
    tls_backup_file "$TLS_DIR/ewallet.p12"
    tls_backup_file "$TLS_DIR/cwallet.sso"
    tls_backup_file "$ORA_TLS_DIR/ewallet.p12"
    tls_backup_file "$ORA_TLS_DIR/cwallet.sso"
    tls_safe_remove_dir "$TLS_DIR"
    tls_safe_remove_dir "$ORA_TLS_DIR"
fi
if [[ ${TLS_REMOVE_CERTS:-NO} == YES ]]; then
    tls_backup_file "$TLS_ROOT_CERT"
    tls_backup_file "$TLS_CSR"
    tls_backup_file "$TLS_SIGNED_CERT"
    tls_safe_remove_dir "$TLS_WORK_DIR"
fi
if [[ ${TLS_REMOVE_CA_CERT:-NO} == YES && -f $TLS_ROOT_CERT ]]; then
    tls_run_as_root rm -f -- "$TLS_CA_ANCHOR_DIR/$(basename -- "$TLS_ROOT_CERT")"
    command -v update-ca-trust >/dev/null 2>&1 && tls_run_as_root update-ca-trust extract
fi
if [[ ${TLS_REMOVE_PCAP:-NO} == YES ]]; then
    find "$(dirname -- "$TLS_CAPTURE_FILE")" -maxdepth 1 -type f -name 'tcpdump_*.pcap' -delete
fi
if [[ ${TLS_REMOVE_CLIENT_USER:-NO} == YES && ${TLS_CLIENT_USER:-} != "$(id -un)" ]]; then
    tls_run_as_root userdel --remove "$TLS_CLIENT_USER"
fi

printf '%s\n' 'TLS configuration cleanup completed. Backups were retained for rollback.'
