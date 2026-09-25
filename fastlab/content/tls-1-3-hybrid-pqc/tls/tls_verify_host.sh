#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

tls_init

SQLNET_FILE="$TNS_ADMIN/sqlnet.ora"
LISTENER_FILE="$TNS_ADMIN/listener.ora"
TNSNAMES_FILE="$TNS_ADMIN/tnsnames.ora"

print_parameters() {
    local label=$1 file=$2
    printf '\n[%s]\n' "$label"
    printf 'File: %s\n' "$file"
    if [[ ! -f $file ]]; then
        printf '  MISSING\n'
        return 0
    fi

    awk '
        /^[[:space:]]*(SSL_CLIENT_AUTHENTICATION|TLS_VERSION|TLS_KEY_EXCHANGE_GROUPS|WALLET_LOCATION)[[:space:]]*=/ {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            printf "  %s\n", line
        }
    ' "$file"
}

print_alias() {
    printf '\n[TNS alias]\n'
    printf 'Alias: %s\n' "$TLS_TNS_ALIAS"
    printf 'File: %s\n' "$TNSNAMES_FILE"
    if [[ ! -f $TNSNAMES_FILE ]]; then
        printf '  MISSING\n'
        return 0
    fi

    awk -v wanted="$TLS_TNS_ALIAS" '
        $0 ~ "^[[:space:]]*" wanted "[[:space:]]*=" { show = 1 }
        show && $0 ~ /^[^[:space:]]+[[:space:]]*=/ && $0 !~ "^[[:space:]]*" wanted "[[:space:]]*=" { exit }
        show { print }
    ' "$TNSNAMES_FILE"
}

printf '%s\n' 'TLS host configuration'
printf 'PDB_NAME: %s\n' "$PDB_NAME"
printf 'TNS alias: %s\n' "$TLS_TNS_ALIAS"
printf 'Service: %s\n' "$TLS_SERVICE_NAME"
printf 'TNS_ADMIN: %s\n' "$TNS_ADMIN"

print_parameters 'sqlnet.ora' "$SQLNET_FILE"
print_parameters 'listener.ora' "$LISTENER_FILE"
print_alias
