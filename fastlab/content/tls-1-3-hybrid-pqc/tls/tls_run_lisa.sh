#!/usr/bin/env bash
# Run from the oracle login shell after Tasks 1 and 2.
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
case ${1:-all} in
    all|setup|test) mode=${1:-all} ;;
    *) echo "Usage: bash $0 [all|setup|test] [PDB_NAME]" >&2; exit 2 ;;
esac
export PDB_NAME=${2:-${PDB_NAME:-pdb1}}
[[ $PDB_NAME =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]] || { echo 'Invalid PDB name.' >&2; exit 2; }
if [[ $mode != test ]]; then
    bash "$SCRIPT_DIR/tls_setup_lisa.sh"
fi
if [[ $mode != setup ]]; then
    # Only the validated PDB name crosses the login boundary. No DB password.
    sudo -iu lisa /bin/bash /home/lisa/tns_admin/tls_test_lisa.sh "$PDB_NAME"
fi
printf 'Task 3 %s complete; you are still in your original shell.\n' "$mode"
