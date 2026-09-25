#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

tls_init
SQLNET_FILE="$TNS_ADMIN/sqlnet.ora"
mkdir -p -- "$TNS_ADMIN" 2>/dev/null || tls_run_as_root mkdir -p -- "$TNS_ADMIN"
tls_touch_file "$SQLNET_FILE"
tls_backup_file "$SQLNET_FILE"

tls_set_parameter "$SQLNET_FILE" SSL_CLIENT_AUTHENTICATION FALSE
if [[ ${TLS_CONFIGURE_TLS13:-YES} == YES ]]; then
    if [[ ${TLS_CRYPTO_PROVIDER:-} == legacy ]]; then
        tls_die 'TLS 1.3 and hybrid key exchange require the next-generation cryptographic provider on Oracle Database 19.32.'
    fi
    tls_set_parameter "$SQLNET_FILE" TLS_VERSION "(${TLS_VERSION_LIST})"
    tls_set_parameter "$SQLNET_FILE" TLS_KEY_EXCHANGE_GROUPS "$TLS_KEY_EXCHANGE_GROUPS"
fi

printf '%s\n' "Updated $SQLNET_FILE:"
cat -- "$SQLNET_FILE"
