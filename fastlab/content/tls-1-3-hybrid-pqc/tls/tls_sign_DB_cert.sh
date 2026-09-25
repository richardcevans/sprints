#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

tls_init
tls_require_password
ORAPKI=$(tls_require_oracle_bin orapki)
tls_require_file "$TLS_CSR"
tls_require_file "$ROOT_TLS_DIR/ewallet.p12"

printf '%s\n' "Signing $TLS_CSR with the root CA wallet."
"$ORAPKI" cert create -wallet "$ROOT_TLS_DIR" -request "$TLS_CSR" \
    -cert "$TLS_SIGNED_CERT" -validity "${TLS_CERT_VALIDITY_DAYS:-3652}" \
    -sign_alg sha256 -pwd "$TLS_PASSWORD" | tls_filter_orapki

printf '%s\n' "Signed certificate: $TLS_SIGNED_CERT"
cat -- "$TLS_SIGNED_CERT"
