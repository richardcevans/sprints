#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

tls_init
SQLPLUS=$(tls_require_oracle_bin sqlplus)
PDB_NAME=$(tls_read_alias "${1:-}")
LOGIN_LINE=$(tls_sqlplus_login_line "$PDB_NAME")

"$SQLPLUS" -s /nolog <<SQL
$LOGIN_LINE
whenever sqlerror exit sql.sqlcode
set lines 140 pages 999
column network_protocol format a25
show user
select sys_context('USERENV','NETWORK_PROTOCOL') as network_protocol,
       sys_context('USERENV','TLS_VERSION') as tls_version,
       sys_context('USERENV','TLS_CIPHERSUITE') as tls_ciphersuite
  from dual;
exit;
SQL
