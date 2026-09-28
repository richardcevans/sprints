#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

case ${1:-} in
    '') ;;
    --replace)
        TLS_REPLACE_CA_CERT=YES
        ;;
    --help|-h)
        printf 'Usage: %s [--replace]\n' "${0##*/}"
        printf '%s\n' '  --replace  Replace a different certificate at the lab trust-anchor path.'
        exit 0
        ;;
    *)
        printf 'Usage: %s [--replace]\n' "${0##*/}" >&2
        exit 2
        ;;
esac
[[ $# -le 1 ]] || { printf 'Usage: %s [--replace]\n' "${0##*/}" >&2; exit 2; }

tls_init
tls_require_file "$TLS_ROOT_CERT"

command -v openssl >/dev/null 2>&1 || tls_die 'openssl is required to validate the CA certificate.'
root_cert_text=$(openssl x509 -in "$TLS_ROOT_CERT" -noout -text 2>/dev/null) || \
    tls_die "TLS_ROOT_CERT is not a readable PEM X.509 certificate: $TLS_ROOT_CERT"
grep -q 'CA:TRUE' <<<"$root_cert_text" || tls_die "TLS_ROOT_CERT is not marked as a CA certificate: $TLS_ROOT_CERT"

command -v update-ca-trust >/dev/null 2>&1 || \
    tls_die 'update-ca-trust is not available. Install/configure ca-certificates for Oracle Linux before continuing.'

tls_run_as_root mkdir -p -- "$TLS_CA_ANCHOR_DIR"
anchor="$TLS_CA_ANCHOR_DIR/$TLS_CA_ANCHOR_NAME"
if [[ -e $anchor ]]; then
    if cmp -s -- "$TLS_ROOT_CERT" "$anchor"; then
        printf 'The same CA certificate is already installed: %s\n' "$anchor"
        exit 0
    fi
    [[ ${TLS_REPLACE_CA_CERT:-NO} == YES ]] || \
        tls_die "Refusing to overwrite a different trust anchor at $anchor. Review it, and then rerun with --replace to replace this lab anchor."
    printf 'Replacing the existing lab trust anchor: %s\n' "$anchor"
fi

tls_run_as_root install -v -o root -g root -m 0644 -- "$TLS_ROOT_CERT" "$anchor"
tls_run_as_root update-ca-trust extract
printf 'Installed lab trust anchor: %s\n' "$anchor"
