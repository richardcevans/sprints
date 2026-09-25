#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

tls_init
SQLPLUS=$(tls_require_oracle_bin sqlplus)
TCPDUMP=$(command -v tcpdump 2>/dev/null || true)
[[ -n $TCPDUMP ]] || tls_die 'tcpdump is not installed. Install it with dnf or yum before running this diagnostic.'
PDB_NAME=$(tls_read_alias "${1:-}")
LOGIN_LINE=$(tls_sqlplus_login_line "$PDB_NAME")

if [[ -n ${TLS_CAPTURE_SQL_FILE:-} ]]; then
    tls_require_file "$TLS_CAPTURE_SQL_FILE"
    CAPTURE_SQL=$(cat -- "$TLS_CAPTURE_SQL_FILE")
else
    CAPTURE_SQL="select sys_context('USERENV','NETWORK_PROTOCOL'), sys_context('USERENV','TLS_VERSION') from dual;"
fi

printf '%s\n' "Capturing port $TLS_CAPTURE_PORT to $TLS_CAPTURE_FILE."
if (( EUID == 0 )); then
    "$TCPDUMP" -nnvvXSs 1514 -i any "port $TLS_CAPTURE_PORT and greater 74" -w "$TLS_CAPTURE_FILE" &
else
    sudo "$TCPDUMP" -nnvvXSs 1514 -i any "port $TLS_CAPTURE_PORT and greater 74" -w "$TLS_CAPTURE_FILE" &
fi
TCPDUMP_PID=$!
trap 'if kill -0 "$TCPDUMP_PID" 2>/dev/null; then kill -INT "$TCPDUMP_PID" 2>/dev/null || true; fi' EXIT
sleep "${TLS_CAPTURE_START_DELAY:-3}"

"$SQLPLUS" -s /nolog <<SQL
$LOGIN_LINE
whenever sqlerror exit sql.sqlcode
set pages 9999
$CAPTURE_SQL
exit;
SQL

sleep "${TLS_CAPTURE_STOP_DELAY:-3}"
kill -INT "$TCPDUMP_PID" 2>/dev/null || true
wait "$TCPDUMP_PID" 2>/dev/null || true
trap - EXIT
printf '%s\n' "Capture complete: $TLS_CAPTURE_FILE"
