#!/usr/bin/env bash

# Shared discovery, compatibility, and safety helpers for the TLS lab scripts.
# Supported target: Oracle Linux 8 or later with Oracle Database 19.32 or 26ai.

if [[ ${TLS_COMMON_LOADED:-0} == 1 ]]; then
    return 0 2>/dev/null || exit 0
fi
TLS_COMMON_LOADED=1

TLS_SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

tls_die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

tls_warn() {
    printf 'WARNING: %s\n' "$*" >&2
}

tls_print_warning() {
    cat >&2 <<'WARNING'
===============================================================================
WARNING: NON-PRODUCTION SYSTEMS ONLY

These scripts can create wallets, change Oracle Net configuration, restart an
Oracle listener or database, change operating-system files, capture network
traffic, install packages, create users, and remove files. Do not run them on
production or shared systems. The person running these scripts accepts full
responsibility for every mistake, outage, data loss, security exposure, and
other fuckup caused by their use.
===============================================================================
WARNING
}

tls_check_oracle_linux() {
    [[ ${TLS_SKIP_OS_CHECK:-NO} == YES ]] && return 0
    if [[ ! -r /etc/os-release ]]; then
        tls_warn 'Cannot identify the operating system; continuing because TLS_SKIP_OS_CHECK is not set.'
        return 0
    fi

    # shellcheck disable=SC1091
    . /etc/os-release
    local major="${VERSION_ID%%.*}"
    if [[ $major =~ ^[0-9]+$ ]] && (( major < 8 )); then
        tls_die "Oracle Linux 8 or later is required; detected ${PRETTY_NAME:-$ID $VERSION_ID}."
    fi
    if [[ ${ID:-} != ol ]]; then
        tls_warn "This script targets Oracle Linux 8 or later; detected ${PRETTY_NAME:-${ID:-unknown}}. Set TLS_SKIP_OS_CHECK=YES only if this is intentional."
    fi
}

tls_oratab_file() {
    if [[ -r /etc/oratab ]]; then
        printf '%s\n' /etc/oratab
    elif [[ -r /var/opt/oracle/oratab ]]; then
        printf '%s\n' /var/opt/oracle/oratab
    else
        return 1
    fi
}

tls_oratab_home_for_sid() {
    local sid=$1 file
    file=$(tls_oratab_file 2>/dev/null || true)
    [[ -n $file ]] || return 0
    awk -F: -v wanted_sid="$sid" '$0 !~ /^[[:space:]]*#/ && $1 == wanted_sid && $2 != "" { print $2; exit }' "$file"
}

tls_resolve_oracle() {
    local home="${ORACLE_HOME:-}" sid="${ORACLE_SID:-}" file candidates count selected
    file=$(tls_oratab_file 2>/dev/null || true)

    if [[ -z $home && -n $sid ]]; then
        home=$(tls_oratab_home_for_sid "$sid")
    fi

    if [[ -z $home && -n $file ]]; then
        candidates=$(awk -F: '$0 !~ /^[[:space:]]*#/ && $1 != "" && $2 != "" { print $1 "|" $2 }' "$file" | sort -u)
        count=$(printf '%s\n' "$candidates" | awk 'NF { n++ } END { print n + 0 }')
        if [[ $count == 1 ]]; then
            selected=${candidates%%|*}
            sid=${selected:-$sid}
            home=${candidates#*|}
        elif [[ $count -gt 1 ]]; then
            tls_die "More than one database is listed in $file. Set ORACLE_SID and/or ORACLE_HOME before running this script."
        fi
    fi

    [[ -n $home ]] || tls_die 'ORACLE_HOME is not set and no unique Oracle home could be discovered from /etc/oratab.'
    [[ -d $home ]] || tls_die "ORACLE_HOME does not exist: $home"

    export ORACLE_HOME
    if [[ -n $sid ]]; then
        export ORACLE_SID=$sid
    fi

    if [[ -z ${ORACLE_BASE:-} ]]; then
        ORACLE_BASE=$(cd -- "$ORACLE_HOME/../.." 2>/dev/null && pwd || true)
    fi
    export ORACLE_BASE
}

tls_oracle_bin() {
    local name=$1
    if [[ -n ${ORACLE_HOME:-} && -x ${ORACLE_HOME}/bin/$name ]]; then
        printf '%s\n' "${ORACLE_HOME}/bin/$name"
    elif command -v "$name" >/dev/null 2>&1; then
        command -v "$name"
    else
        return 1
    fi
}

tls_require_oracle_bin() {
    local name=$1 path
    path=$(tls_oracle_bin "$name" 2>/dev/null || true)
    [[ -n $path ]] || tls_die "Cannot find $name under ORACLE_HOME or PATH."
    printf '%s\n' "$path"
}

tls_load_defaults() {
    export TNS_ADMIN="${TNS_ADMIN:-${ORACLE_HOME:-$TLS_SCRIPT_DIR}/network/admin}"
    export TLS_WORK_DIR="${TLS_WORK_DIR:-${DBSEC_LABS:-$TLS_SCRIPT_DIR/certificates}}"
    export ORACLE_BASE="${ORACLE_BASE:-$TLS_SCRIPT_DIR}"
    export ORACLE_SID="${ORACLE_SID:-oracle}"
    export WALLET_ROOT="${WALLET_ROOT:-$ORACLE_BASE/admin/$ORACLE_SID/wallet}"
    export ROOT_TLS_DIR="${ROOT_TLS_DIR:-$TLS_WORK_DIR/rootCA}"
    export DB_TLS_DIR="${DB_TLS_DIR:-$TLS_WORK_DIR/db_wallet}"
    export TLS_DIR="${TLS_DIR:-$WALLET_ROOT/tls}"
    export ORA_TLS_DIR="${ORA_TLS_DIR:-$TNS_ADMIN/wallet}"
    export TLS_CLIENT_USER="${TLS_CLIENT_USER:-${USER:-oracle}}"
    if [[ -z ${TLS_CLIENT_HOME:-} ]]; then
        TLS_CLIENT_HOME=$(getent passwd "$TLS_CLIENT_USER" 2>/dev/null | cut -d: -f6 || true)
        TLS_CLIENT_HOME="${TLS_CLIENT_HOME:-${HOME:-$TLS_SCRIPT_DIR}}"
    fi
    export TLS_CLIENT_HOME
    export DAN_TNS_DIR="${DAN_TNS_DIR:-${TLS_CLIENT_TNS_ADMIN:-${TNS_ADMIN:-$TLS_CLIENT_HOME/tns_admin}}}"
    export DAN_CLIENT_TLS_DIR="${DAN_CLIENT_TLS_DIR:-$DAN_TNS_DIR/client_wallet}"
    export TLS_CLIENT_TNS_ADMIN="$DAN_TNS_DIR"
    export TLS_SERVER_HOST="${TLS_SERVER_HOST:-${TLS_HOST:-$(hostname -f 2>/dev/null || hostname)}}"
    export TLS_TCP_PORT="${TLS_TCP_PORT:-1521}"
    export TLS_TCPS_PORT="${TLS_TCPS_PORT:-2484}"
    export PDB_NAME="${PDB_NAME:-pdb1}"
    export TLS_TNS_ALIAS="${TLS_TNS_ALIAS:-${PDB_NAME}_tls}"
    export TLS_SERVICE_NAME="${TLS_SERVICE_NAME:-$PDB_NAME}"
    export TLS_LISTENER_NAME="${TLS_LISTENER_NAME:-LISTENER_TLS}"
    export TLS_VERSION_LIST="${TLS_VERSION_LIST:-TLSv1.2,TLSv1.3}"
    export TLS_CONFIGURE_TLS13="${TLS_CONFIGURE_TLS13:-YES}"
    export TLS_KEY_EXCHANGE_GROUPS="${TLS_KEY_EXCHANGE_GROUPS:-hybrid,ec}"
    export TLS_CONFIGURE_HYBRID="${TLS_CONFIGURE_HYBRID:-NO}"
    export TLS_ROOT_DN="${TLS_ROOT_DN:-C=US,CN=Oracle TLS Lab Root CA}"
    export TLS_SERVER_DN="${TLS_SERVER_DN:-CN=$TLS_SERVER_HOST,OU=Oracle TLS Lab,O=Oracle,C=US}"
    export TLS_ROOT_CERT="${TLS_ROOT_CERT:-$ROOT_TLS_DIR/rootCA.crt}"
    export TLS_CSR="${TLS_CSR:-$DB_TLS_DIR/dbserver.csr}"
    export TLS_SIGNED_CERT="${TLS_SIGNED_CERT:-$DB_TLS_DIR/dbserver-signed.crt}"
    export TLS_PASSWORD="${TLS_PASSWORD:-${TLS_WALLET_PASSWORD:-${DBUSR_PWD:-}}}"
    export TLS_CA_ANCHOR_DIR="${TLS_CA_ANCHOR_DIR:-/etc/pki/ca-trust/source/anchors}"
    export TLS_CAPTURE_PORT="${TLS_CAPTURE_PORT:-$TLS_TCPS_PORT}"
    export TLS_CAPTURE_FILE="${TLS_CAPTURE_FILE:-$TLS_SCRIPT_DIR/tcpdump_${TLS_CAPTURE_PORT}.pcap}"
}

tls_init() {
    tls_print_warning
    tls_check_oracle_linux
    if [[ ${1:-} != --no-oracle ]]; then
        tls_resolve_oracle
    fi
    tls_load_defaults
    printf 'Using PDB_NAME=%s\n' "$PDB_NAME"
    printf 'Using ORACLE_HOME=%s ORACLE_SID=%s TNS_ADMIN=%s\n' "${ORACLE_HOME:-<not set>}" "${ORACLE_SID:-<not set>}" "$TNS_ADMIN"
}

tls_require_password() {
    [[ -n ${TLS_PASSWORD:-} ]] || tls_die 'Set TLS_PASSWORD or DBUSR_PWD; wallet commands require a password.'
}

tls_run_as_root() {
    if (( EUID == 0 )); then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        tls_die "Root privileges are required for: $*"
    fi
}

tls_file_writable() {
    local file=$1
    [[ -w $file || ( ! -e $file && -w $(dirname -- "$file") ) ]]
}

tls_touch_file() {
    local file=$1
    if [[ -e $file ]]; then
        return 0
    elif tls_file_writable "$file"; then
        touch "$file"
    else
        tls_run_as_root touch "$file"
    fi
}

tls_edit_in_place() {
    local file=$1
    shift
    if tls_file_writable "$file"; then
        sed -i "$@" "$file"
    else
        tls_run_as_root sed -i "$@" "$file"
    fi
}

tls_append_line() {
    local file=$1 line=$2
    grep -Fqx -- "$line" "$file" 2>/dev/null && return 0
    if tls_file_writable "$file"; then
        printf '%s\n' "$line" >> "$file"
    else
        printf '%s\n' "$line" | tls_run_as_root tee -a "$file" >/dev/null
    fi
}

tls_append_raw_line() {
    local file=$1 line=$2
    if tls_file_writable "$file"; then
        printf '%s\n' "$line" >> "$file"
    else
        printf '%s\n' "$line" | tls_run_as_root tee -a "$file" >/dev/null
    fi
}

tls_filter_orphan_tns_entries() {
    local file=$1
    awk '
        function parentheses(line, opened, closed) {
            opened = gsub(/\(/, "", line)
            closed = gsub(/\)/, "", line)
            return opened - closed
        }
        {
            if (!skipping && $0 ~ /^[[:space:]]*=[[:space:]]*$/) {
                skipping = 1
                depth = 0
                saw_descriptor = 0
                next
            }
            if (skipping) {
                line = $0
                depth += parentheses(line)
                if (line ~ /\(/) {
                    saw_descriptor = 1
                }
                if (saw_descriptor && depth <= 0) {
                    skipping = 0
                }
                next
            }
            print
        }
    ' "$file"
}

tls_remove_orphan_tns_entries() {
    local file=$1 temp
    [[ -f $file ]] || return 0

    if tls_file_writable "$file" && [[ -w $(dirname -- "$file") ]]; then
        temp=$(mktemp "${file}.tls-fastlab.XXXXXX")
        tls_filter_orphan_tns_entries "$file" > "$temp"
        chmod --reference="$file" -- "$temp"
        if cmp -s -- "$file" "$temp"; then
            rm -f -- "$temp"
        else
            mv -f -- "$temp" "$file"
            printf 'Removed orphan TNS entry from %s\n' "$file"
        fi
    else
        temp=$(tls_run_as_root mktemp "${file}.tls-fastlab.XXXXXX")
        tls_filter_orphan_tns_entries "$file" | tls_run_as_root tee "$temp" >/dev/null
        tls_run_as_root chmod --reference="$file" -- "$temp"
        tls_run_as_root chown --reference="$file" -- "$temp"
        if tls_run_as_root cmp -s -- "$file" "$temp"; then
            tls_run_as_root rm -f -- "$temp"
        else
            tls_run_as_root mv -f -- "$temp" "$file"
            printf 'Removed orphan TNS entry from %s\n' "$file"
        fi
    fi
}

tls_set_parameter() {
    local file=$1 key=$2 value=$3
    tls_edit_in_place "$file" -E "/^[[:space:]]*${key}[[:space:]]*=/d"
    tls_append_line "$file" "$key = $value"
}

tls_backup_file() {
    local file=$1 backup
    [[ -e $file ]] || return 0
    backup="${file}.before-tls-fastlab"
    if [[ -e $backup ]]; then
        backup="${file}.before-tls-fastlab.$(date +%Y%m%d%H%M%S)"
    fi
    if tls_file_writable "$file" && [[ -w $(dirname -- "$file") ]]; then
        cp -p -- "$file" "$backup"
    else
        tls_run_as_root cp -p -- "$file" "$backup"
    fi
    printf 'Backup: %s\n' "$backup"
}

tls_filter_orapki() {
    grep -i -v -E '^Oracle PKI|^Version|^Copyright' || true
}

tls_sqlplus_login_line() {
    local alias=$1
    if [[ -n ${DB_CONNECT_STRING:-} ]]; then
        printf 'connect %s\n' "$DB_CONNECT_STRING"
    elif [[ -n ${DBUSR_SYSTEM:-} && -n ${DBUSR_PWD:-} ]]; then
        printf 'connect %s/%s@%s\n' "$DBUSR_SYSTEM" "$DBUSR_PWD" "$alias"
    else
        tls_die 'Set DB_CONNECT_STRING or both DBUSR_SYSTEM and DBUSR_PWD for SQL*Plus login.'
    fi
}

tls_chown_path() {
    local path=$1 user=${2:-$TLS_CLIENT_USER} group
    [[ -e $path ]] || return 0
    id "$user" >/dev/null 2>&1 || return 0
    group=$(id -gn "$user")
    tls_run_as_root chown -R "$user:$group" -- "$path"
}

tls_require_file() {
    [[ -f $1 ]] || tls_die "Required file does not exist: $1"
}

tls_read_alias() {
    if [[ -n ${1:-} ]]; then
        printf '%s\n' "$1"
    elif [[ -t 0 ]]; then
        read -r -p "TNS alias [${TLS_TNS_ALIAS}]: " alias
        printf '%s\n' "${alias:-$TLS_TNS_ALIAS}"
    else
        printf '%s\n' "$TLS_TNS_ALIAS"
    fi
}

tls_confirm_destructive() {
    [[ ${TLS_CONFIRM_DESTRUCTIVE:-NO} == YES || ${1:-} == --yes-i-understand ]] && return 0
    if [[ -t 0 ]]; then
        local answer
        read -r -p 'Type YES to continue with destructive changes: ' answer
        [[ $answer == YES ]] && return 0
    fi
    tls_die 'Destructive changes were not confirmed. Set TLS_CONFIRM_DESTRUCTIVE=YES or pass --yes-i-understand.'
}

tls_safe_remove_dir() {
    local dir=$1
    [[ -n $dir && $dir != / && $dir != "$ORACLE_HOME" && $dir != "$ORACLE_BASE" ]] || tls_die "Refusing to remove unsafe directory: $dir"
    [[ -d $dir ]] && tls_run_as_root rm -rf -- "$dir"
}
