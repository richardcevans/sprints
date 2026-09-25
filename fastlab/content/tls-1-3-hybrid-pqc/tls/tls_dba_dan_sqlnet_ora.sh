#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

tls_init
CLIENT_SQLNET="$TLS_CLIENT_TNS_ADMIN/sqlnet.ora"
mkdir -p -- "$TLS_CLIENT_TNS_ADMIN" 2>/dev/null || tls_run_as_root mkdir -p -- "$TLS_CLIENT_TNS_ADMIN"
tls_touch_file "$CLIENT_SQLNET"
tls_backup_file "$CLIENT_SQLNET"

tls_set_parameter "$CLIENT_SQLNET" SSL_CLIENT_AUTHENTICATION FALSE
if [[ ${TLS_CONFIGURE_TLS13:-YES} == YES ]]; then
    tls_set_parameter "$CLIENT_SQLNET" TLS_VERSION "(${TLS_VERSION_LIST})"
    tls_set_parameter "$CLIENT_SQLNET" TLS_KEY_EXCHANGE_GROUPS "$TLS_KEY_EXCHANGE_GROUPS"
fi
if [[ ${TLS_CHOWN_CLIENT_FILES:-NO} == YES ]]; then
    tls_chown_path "$TLS_CLIENT_TNS_ADMIN" "$TLS_CLIENT_USER"
fi

printf '%s\n' "Updated $CLIENT_SQLNET:"
cat -- "$CLIENT_SQLNET"
