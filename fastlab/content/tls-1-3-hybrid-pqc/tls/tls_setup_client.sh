#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

tls_init
CLIENT_TNS_ADMIN="$TLS_CLIENT_TNS_ADMIN"
CLIENT_SQLNET="$CLIENT_TNS_ADMIN/sqlnet.ora"
CLIENT_TNSNAMES="$CLIENT_TNS_ADMIN/tnsnames.ora"

if [[ ${TLS_CONFIGURE_TLS13:-YES} == YES && ${TLS_CRYPTO_PROVIDER:-} == legacy ]]; then
    tls_die 'TLS 1.3 and hybrid key exchange require the next-generation cryptographic provider on Oracle Database 19.32.'
fi

if [[ ! -d $TLS_CLIENT_WALLET_DIR ]]; then
    tls_die "Client wallet directory does not exist: $TLS_CLIENT_WALLET_DIR. Set TLS_CLIENT_WALLET_DIR to the existing client trust wallet."
fi
if [[ ! -f $TLS_CLIENT_WALLET_DIR/cwallet.sso && ! -f $TLS_CLIENT_WALLET_DIR/ewallet.p12 ]]; then
    tls_die "No client wallet was found in $TLS_CLIENT_WALLET_DIR. This FastLab does not create wallets."
fi
tls_backup_directory "$TLS_CLIENT_WALLET_DIR"

# Back up both client files before creating a directory or touching anything in
# the client configuration location. TNS_ADMIN can point to this directory.
tls_backup_file "$CLIENT_SQLNET"
tls_backup_file "$CLIENT_TNSNAMES"

mkdir -p -- "$CLIENT_TNS_ADMIN" 2>/dev/null || tls_run_as_root mkdir -p -- "$CLIENT_TNS_ADMIN"
tls_touch_file "$CLIENT_SQLNET"
tls_touch_file "$CLIENT_TNSNAMES"
tls_remove_orphan_tns_entries "$CLIENT_TNSNAMES"

tls_set_parameter "$CLIENT_SQLNET" WALLET_LOCATION "(SOURCE = (METHOD = FILE) (METHOD_DATA = (DIRECTORY = $TLS_CLIENT_WALLET_DIR)))"
tls_set_parameter "$CLIENT_SQLNET" SSL_CLIENT_AUTHENTICATION FALSE
if [[ ${TLS_CONFIGURE_TLS13:-YES} == YES ]]; then
    tls_set_parameter "$CLIENT_SQLNET" TLS_VERSION "(${TLS_VERSION_LIST})"
    if [[ ${TLS_CONFIGURE_HYBRID:-NO} == YES ]]; then
        tls_set_parameter "$CLIENT_SQLNET" TLS_KEY_EXCHANGE_GROUPS "$TLS_KEY_EXCHANGE_GROUPS"
    else
        tls_edit_in_place "$CLIENT_SQLNET" -E '/^[[:space:]]*TLS_KEY_EXCHANGE_GROUPS[[:space:]]*=.*/d'
    fi
fi

if ! grep -Eiq "^[[:space:]]*${TLS_TNS_ALIAS}[[:space:]]*=" "$CLIENT_TNSNAMES"; then
    while IFS= read -r line; do
        [[ -n $line ]] && tls_append_raw_line "$CLIENT_TNSNAMES" "$line"
    done <<EOF

$TLS_TNS_ALIAS =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCPS)(HOST = $TLS_SERVER_HOST)(PORT = $TLS_TCPS_PORT))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = $TLS_SERVICE_NAME)
    )
  )
EOF
fi

if [[ ${TLS_CHOWN_CLIENT_FILES:-NO} == YES ]]; then
    tls_chown_path "$CLIENT_TNS_ADMIN" "$TLS_CLIENT_USER"
fi

printf '%s\n' "Updated $CLIENT_SQLNET:"
cat -- "$CLIENT_SQLNET"
printf '%s\n' "Updated $CLIENT_TNSNAMES:"
cat -- "$CLIENT_TNSNAMES"
