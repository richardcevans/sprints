#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

tls_init
tls_require_password
ORAPKI=$(tls_require_oracle_bin orapki)
tls_require_file "$TLS_ROOT_CERT"

printf '%s\n' "Creating the database wallet and certificate request in $DB_TLS_DIR."
tls_backup_file "$DB_TLS_DIR/ewallet.p12"
tls_backup_file "$DB_TLS_DIR/cwallet.sso"
tls_backup_file "$TLS_CSR"
mkdir -p -- "$DB_TLS_DIR"

if [[ ! -f $DB_TLS_DIR/ewallet.p12 && ! -f $DB_TLS_DIR/cwallet.sso ]]; then
    "$ORAPKI" wallet create -wallet "$DB_TLS_DIR" -pwd "$TLS_PASSWORD" -auto_login -compat_v12 | tls_filter_orapki
else
    tls_warn "Database wallet already exists; not recreating it: $DB_TLS_DIR"
fi

"$ORAPKI" wallet add -wallet "$DB_TLS_DIR" -trusted_cert -cert "$TLS_ROOT_CERT" \
    -pwd "$TLS_PASSWORD" | tls_filter_orapki
"$ORAPKI" wallet add -wallet "$DB_TLS_DIR" -keysize 2048 -dn "$TLS_SERVER_DN" \
    -pwd "$TLS_PASSWORD" | tls_filter_orapki
"$ORAPKI" wallet export -wallet "$DB_TLS_DIR" -dn "$TLS_SERVER_DN" \
    -request "$TLS_CSR" -pwd "$TLS_PASSWORD" | tls_filter_orapki

printf '%s\n' 'Database wallet contents:'
"$ORAPKI" wallet display -wallet "$DB_TLS_DIR" | tls_filter_orapki
printf '%s\n' "Certificate request: $TLS_CSR"
