#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

tls_init --no-oracle

if command -v sqlplus >/dev/null 2>&1; then
    printf '%s\n' "SQL*Plus is already available: $(command -v sqlplus)"
    exit 0
fi

PKG_MGR=$(command -v dnf 2>/dev/null || command -v yum 2>/dev/null || true)
[[ -n $PKG_MGR ]] || tls_die 'Neither dnf nor yum is available on this Oracle Linux host.'

DOWNLOAD_DIR="${ORACLE_IC_DOWNLOAD_DIR:-$PWD}"
BASIC_RPM="${ORACLE_IC_BASIC_RPM:-}"
SQLPLUS_RPM="${ORACLE_IC_SQLPLUS_RPM:-}"
BASIC_URL="${ORACLE_IC_BASIC_RPM_URL:-}"
SQLPLUS_URL="${ORACLE_IC_SQLPLUS_RPM_URL:-}"
mkdir -p -- "$DOWNLOAD_DIR"

download_rpm() {
    local url=$1 target=$2
    [[ -n $url ]] || return 0
    if [[ -f $target ]]; then
        return 0
    fi
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 --output "$target" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$target" "$url"
    else
        tls_die 'Install curl or wget, or provide local ORACLE_IC_BASIC_RPM and ORACLE_IC_SQLPLUS_RPM files.'
    fi
}

if [[ -z $BASIC_RPM && -n $BASIC_URL ]]; then
    BASIC_RPM="$DOWNLOAD_DIR/$(basename -- "$BASIC_URL")"
    download_rpm "$BASIC_URL" "$BASIC_RPM"
fi
if [[ -z $SQLPLUS_RPM && -n $SQLPLUS_URL ]]; then
    SQLPLUS_RPM="$DOWNLOAD_DIR/$(basename -- "$SQLPLUS_URL")"
    download_rpm "$SQLPLUS_URL" "$SQLPLUS_RPM"
fi

[[ -f $BASIC_RPM && -f $SQLPLUS_RPM ]] || tls_die 'Provide ORACLE_IC_BASIC_RPM and ORACLE_IC_SQLPLUS_RPM, or the matching *_RPM_URL values from the Oracle Instant Client download page. This avoids assuming an obsolete 19c package version.'

tls_run_as_root "$PKG_MGR" install -y "$BASIC_RPM" "$SQLPLUS_RPM"
printf '%s\n' 'Oracle Instant Client Basic and SQL*Plus packages installed.'
