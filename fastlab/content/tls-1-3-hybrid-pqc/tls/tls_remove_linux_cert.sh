#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

tls_init --no-oracle
tls_confirm_destructive "${1:-}"

command -v update-ca-trust >/dev/null 2>&1 || \
    tls_die 'update-ca-trust is not available. Install/configure ca-certificates for Oracle Linux before continuing.'

anchor="$TLS_CA_ANCHOR_DIR/$TLS_CA_ANCHOR_NAME"
if [[ ! -e $anchor ]]; then
    printf 'The lab trust anchor is not installed: %s\n' "$anchor"
    exit 0
fi

printf 'Removing lab trust anchor: %s\n' "$anchor"
tls_run_as_root rm -f -- "$anchor"
tls_run_as_root update-ca-trust extract
[[ ! -e $anchor ]] || tls_die "The lab trust anchor still exists: $anchor"
printf '%s\n' 'The lab trust anchor was removed from the Oracle Linux trust store.'
