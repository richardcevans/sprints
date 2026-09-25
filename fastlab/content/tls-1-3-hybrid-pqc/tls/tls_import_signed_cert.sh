#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

tls_init
tls_require_password
ORAPKI=$(tls_require_oracle_bin orapki)
tls_require_file "$TLS_SIGNED_CERT"

printf '%s\n' 'Importing the signed database certificate into the database wallet.'
tls_backup_file "$DB_TLS_DIR/ewallet.p12"
tls_backup_file "$DB_TLS_DIR/cwallet.sso"
"$ORAPKI" wallet display -wallet "$DB_TLS_DIR" -pwd "$TLS_PASSWORD" | tls_filter_orapki
"$ORAPKI" wallet add -wallet "$DB_TLS_DIR" -user_cert -cert "$TLS_SIGNED_CERT" \
    -pwd "$TLS_PASSWORD" | tls_filter_orapki
"$ORAPKI" wallet display -wallet "$DB_TLS_DIR" -pwd "$TLS_PASSWORD" | tls_filter_orapki
