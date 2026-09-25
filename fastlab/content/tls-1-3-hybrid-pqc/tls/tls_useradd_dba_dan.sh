#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

export TLS_CLIENT_USER="${TLS_CLIENT_USER:-dba_dan}"
tls_init --no-oracle

if id "$TLS_CLIENT_USER" >/dev/null 2>&1; then
    printf '%s\n' "OS user already exists: $TLS_CLIENT_USER"
else
    tls_run_as_root useradd --create-home "$TLS_CLIENT_USER"
    id "$TLS_CLIENT_USER"
fi
