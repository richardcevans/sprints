#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

tls_init --no-oracle
tls_confirm_destructive "${1:-}"

if ! id lisa >/dev/null 2>&1; then
    printf '%s\n' 'The lisa operating-system account does not exist. No changes made.'
    exit 0
fi

[[ $(id -un) != lisa ]] || tls_die 'Do not run this script from the lisa account.'
lisa_home=$(getent passwd lisa | cut -d: -f6)
[[ $lisa_home == /home/lisa ]] || tls_die "Refusing to remove lisa because her home is not /home/lisa: $lisa_home"

if pgrep -u lisa >/dev/null 2>&1; then
    tls_die 'Lisa has running processes. Exit her sessions and stop her processes before retrying.'
fi

printf '%s\n' 'Removing the lisa account and /home/lisa.'
tls_run_as_root userdel --remove lisa
id lisa >/dev/null 2>&1 && tls_die 'The lisa account still exists after userdel.'
[[ ! -e /home/lisa ]] || tls_warn '/home/lisa still exists; review and remove it manually if appropriate.'
printf '%s\n' 'The lisa operating-system account was removed.'
