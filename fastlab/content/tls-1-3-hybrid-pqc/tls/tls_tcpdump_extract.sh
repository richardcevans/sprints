#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

tls_init --no-oracle
CAPTURE_FILE="${TLS_CAPTURE_FILE:-$TLS_SCRIPT_DIR/tcpdump_${TLS_CAPTURE_PORT}.pcap}"
tls_require_file "$CAPTURE_FILE"
STRINGS=$(command -v strings 2>/dev/null || true)
[[ -n $STRINGS ]] || tls_die 'strings is not installed.'

printf '%s\n' "Extracting printable email-like values from $CAPTURE_FILE."
"$STRINGS" "$CAPTURE_FILE" \
    | grep -Eio '[[:alnum:]._+-]+@[[:alnum:].-]+' \
    | sort -fu \
    | tail -25 || true
