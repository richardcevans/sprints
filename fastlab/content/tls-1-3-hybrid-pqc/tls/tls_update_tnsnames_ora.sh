#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

tls_init
TNSNAMES_FILE="$TNS_ADMIN/tnsnames.ora"
mkdir -p -- "$TNS_ADMIN" 2>/dev/null || tls_run_as_root mkdir -p -- "$TNS_ADMIN"
tls_touch_file "$TNSNAMES_FILE"
tls_backup_file "$TNSNAMES_FILE"

if grep -Eiq "^[[:space:]]*${TLS_TNS_ALIAS}[[:space:]]*=" "$TNSNAMES_FILE"; then
    printf '%s\n' "TNS alias already exists: $TLS_TNS_ALIAS"
else
    while IFS= read -r line; do
        [[ -n $line ]] && tls_append_line "$TNSNAMES_FILE" "$line"
    done <<EOF

$TLS_TNS_ALIAS =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCPS)(HOST = $TLS_SERVER_HOST)(PORT = $TLS_TCPS_PORT))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = $TLS_SERVICE_NAME)
    )
EOF
    if [[ -n ${TLS_TNS_TLS_VERSION:-} ]]; then
        tls_append_line "$TNSNAMES_FILE" "    (SECURITY = (TLS_VERSION = $TLS_TNS_TLS_VERSION))"
    fi
    tls_append_line "$TNSNAMES_FILE" '  )'
    tls_append_line "$TNSNAMES_FILE" ')'
fi

printf '%s\n' "Updated $TNSNAMES_FILE:"
tail -30 -- "$TNSNAMES_FILE"
