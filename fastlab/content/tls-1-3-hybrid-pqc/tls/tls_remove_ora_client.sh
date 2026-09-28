#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

tls_init --no-oracle
tls_confirm_destructive "${1:-}"

# Remove only the RPMs installed by tls_install_lisa_ic.sh. Do not autoremove
# dependencies or touch other Oracle Instant Client packages.
release_package="oracle-instantclient-release-26ai-el${VERSION_ID%%.*}"
lab_packages=(
    oracle-instantclient-basic
    oracle-instantclient-sqlplus
    "$release_package"
)
installed_packages=()

for package in "${lab_packages[@]}"; do
    if rpm -q "$package" >/dev/null 2>&1; then
        installed_packages+=("$package")
    fi
done

if [[ ${#installed_packages[@]} == 0 ]]; then
    printf '%s\n' 'The Oracle Instant Client RPMs installed by this lab are not present. No changes made.'
    exit 0
fi

printf '%s\n' 'Removing these lab Instant Client RPMs:'
printf '  %s\n' "${installed_packages[@]}"
tls_run_as_root dnf -v --setopt=clean_requirements_on_remove=False remove -y "${installed_packages[@]}"

for package in "${installed_packages[@]}"; do
    rpm -q "$package" >/dev/null 2>&1 && tls_die "Package is still installed: $package"
done
printf '%s\n' 'The lab Instant Client RPMs were removed. Other Instant Client packages were not requested for removal.'
