#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

tls_init
CLIENT_TNSNAMES="$TLS_CLIENT_TNS_ADMIN/tnsnames.ora"
mkdir -p -- "$TLS_CLIENT_TNS_ADMIN" 2>/dev/null || tls_run_as_root mkdir -p -- "$TLS_CLIENT_TNS_ADMIN"
tls_touch_file "$CLIENT_TNSNAMES"
tls_backup_file "$CLIENT_TNSNAMES"

if ! grep -Eiq "^[[:space:]]*${TLS_TNS_ALIAS}[[:space:]]*=" "$CLIENT_TNSNAMES"; then
    while IFS= read -r line; do
        [[ -n $line ]] && tls_append_line "$CLIENT_TNSNAMES" "$line"
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
    tls_chown_path "$TLS_CLIENT_TNS_ADMIN" "$TLS_CLIENT_USER"
fi

printf '%s\n' "Updated $CLIENT_TNSNAMES:"
cat -- "$CLIENT_TNSNAMES"
