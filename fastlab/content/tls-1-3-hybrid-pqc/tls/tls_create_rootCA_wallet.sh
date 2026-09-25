#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

tls_init
tls_require_password
ORAPKI=$(tls_require_oracle_bin orapki)

printf '%s\n' 'Creating the root CA wallet and self-signed certificate.'
tls_backup_file "$ROOT_TLS_DIR/ewallet.p12"
tls_backup_file "$ROOT_TLS_DIR/cwallet.sso"
tls_backup_file "$TLS_ROOT_CERT"
mkdir -p -- "$ROOT_TLS_DIR"

if [[ ! -f $ROOT_TLS_DIR/ewallet.p12 && ! -f $ROOT_TLS_DIR/cwallet.sso ]]; then
    "$ORAPKI" wallet create -wallet "$ROOT_TLS_DIR" -pwd "$TLS_PASSWORD" -auto_login -compat_v12 | tls_filter_orapki
else
    tls_warn "Root wallet already exists; not recreating it: $ROOT_TLS_DIR"
fi

if ! "$ORAPKI" wallet display -wallet "$ROOT_TLS_DIR" 2>/dev/null | grep -q "$TLS_ROOT_DN"; then
    "$ORAPKI" wallet add -wallet "$ROOT_TLS_DIR" -dn "$TLS_ROOT_DN" -keysize 2048 \
        -sign_alg sha256 -self_signed -validity "${TLS_CERT_VALIDITY_DAYS:-3652}" \
        -pwd "$TLS_PASSWORD" | tls_filter_orapki
fi

"$ORAPKI" wallet export -wallet "$ROOT_TLS_DIR" -dn "$TLS_ROOT_DN" \
    -cert "$TLS_ROOT_CERT" -pwd "$TLS_PASSWORD" | tls_filter_orapki

printf '%s\n' 'Root wallet contents:'
ls -l -- "$ROOT_TLS_DIR"
"$ORAPKI" wallet display -wallet "$ROOT_TLS_DIR" | tls_filter_orapki
printf '%s\n' "Root certificate: $TLS_ROOT_CERT"
