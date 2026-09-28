#!/usr/bin/env bash
set -euo pipefail
[[ $(id -un) == lisa && $HOME == /home/lisa ]] || { echo 'Run this test as Lisa with home /home/lisa.' >&2; exit 1; }
PDB_NAME=${1:-${PDB_NAME:-pdb1}}
[[ $PDB_NAME =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]] || { echo 'Invalid PDB name.' >&2; exit 1; }
export TNS_ADMIN=/home/lisa/tns_admin
unset ORACLE_HOME ORACLE_SID TWO_TASK LOCAL SQLPATH ORACLE_PATH LD_LIBRARY_PATH LD_PRELOAD
# Select the installed Instant Client RPM binary, never database-home SQL*Plus.
mapfile -t bins < <(rpm -ql oracle-instantclient-sqlplus | grep -E '^/usr/lib/oracle/[^/]+/client64/bin/sqlplus$')
[[ ${#bins[@]} == 1 && -x ${bins[0]} ]] || { echo 'Expected one RPM-owned Instant Client SQL*Plus binary.' >&2; exit 1; }
SQLPLUS_BIN=${bins[0]}
sqlplus_dir=$(dirname -- "$SQLPLUS_BIN")
export PATH="$sqlplus_dir:/usr/bin:/bin"
cd -- "$TNS_ADMIN"
"$SQLPLUS_BIN" -v
failed=0
for version in 1.2 1.3; do
    alias_name=${PDB_NAME}_tls${version/./}
    printf '\nTesting %s as database user system. Enter its database password when prompted.\n' "$alias_name"
    # Password is read by SQL*Plus, never a shell variable or command-line argument.
    if "$SQLPLUS_BIN" -L "system@$alias_name" @"$TNS_ADMIN/tls_test_lisa.sql" "TLSv$version"; then
        printf 'PASS: %s negotiated tcps / TLSv%s.\n' "$alias_name" "$version"
    else
        printf 'FAIL: %s (connection, query, or TLS assertion failed).\n' "$alias_name" >&2
        failed=1
    fi
done
exit "$failed"
