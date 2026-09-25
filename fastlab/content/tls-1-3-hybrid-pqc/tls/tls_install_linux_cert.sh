#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

tls_init
tls_require_password
ORAPKI=$(tls_require_oracle_bin orapki)
tls_require_file "$TLS_ROOT_CERT"

tls_run_as_root mkdir -p -- "$TLS_CA_ANCHOR_DIR"
tls_run_as_root cp -p -- "$TLS_ROOT_CERT" "$TLS_CA_ANCHOR_DIR/$(basename -- "$TLS_ROOT_CERT")"

if command -v update-ca-trust >/dev/null 2>&1; then
    tls_run_as_root update-ca-trust extract
else
    tls_warn 'update-ca-trust is not available; the certificate was copied but the Linux trust store was not rebuilt.'
fi

printf '%s\n' "Installed $(basename -- "$TLS_ROOT_CERT") in $TLS_CA_ANCHOR_DIR."
