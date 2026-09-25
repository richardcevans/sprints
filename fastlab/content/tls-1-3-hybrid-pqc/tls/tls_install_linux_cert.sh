#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

tls_init
tls_require_file "$TLS_ROOT_CERT"

command -v openssl >/dev/null 2>&1 || tls_die 'openssl is required to validate the CA certificate.'
openssl x509 -in "$TLS_ROOT_CERT" -noout -subject -issuer >/dev/null 2>&1 || \
    tls_die "TLS_ROOT_CERT is not a readable PEM X.509 certificate: $TLS_ROOT_CERT"
openssl x509 -in "$TLS_ROOT_CERT" -noout -text | grep -q 'CA:TRUE' || \
    tls_die "TLS_ROOT_CERT is not marked as a CA certificate: $TLS_ROOT_CERT"

command -v update-ca-trust >/dev/null 2>&1 || \
    tls_die 'update-ca-trust is not available. Install/configure ca-certificates for Oracle Linux before continuing.'

tls_run_as_root mkdir -p -- "$TLS_CA_ANCHOR_DIR"
anchor="$TLS_CA_ANCHOR_DIR/${TLS_CA_ANCHOR_NAME:-tls-fastlab-root-ca.crt}"
if [[ -e $anchor ]]; then
    if cmp -s -- "$TLS_ROOT_CERT" "$anchor"; then
        printf 'The same CA certificate is already installed: %s\n' "$anchor"
        exit 0
    fi
    tls_die "Refusing to overwrite a different trust anchor at $anchor. Set TLS_CA_ANCHOR_NAME to a new filename after reviewing the existing file."
fi

tls_run_as_root install -v -o root -g root -m 0644 -- "$TLS_ROOT_CERT" "$anchor"
tls_run_as_root update-ca-trust extract
