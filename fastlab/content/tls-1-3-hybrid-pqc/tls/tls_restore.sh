#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

tls_init
tls_confirm_destructive "${1:-}"

LSNRCTL=$(tls_require_oracle_bin lsnrctl)
SQLPLUS=$(tls_require_oracle_bin sqlplus)
BACKUP_SELECTOR="${TLS_RESTORE_BACKUP:-original}"
RESTORE_HOST="${TLS_RESTORE_HOST:-YES}"
RESTORE_CLIENT="${TLS_RESTORE_CLIENT:-YES}"

backup_for() {
    local file=$1
    if [[ $BACKUP_SELECTOR == original ]]; then
        printf '%s.before-tls-fastlab\n' "$file"
    else
        printf '%s.before-tls-fastlab.%s\n' "$file" "$BACKUP_SELECTOR"
    fi
}

restore_one() {
    local file=$1 backup
    backup=$(backup_for "$file")
    if [[ -f $backup ]]; then
        tls_restore_file_from_backup "$file" "$backup"
    else
        tls_warn "No restore backup found for $file: $backup"
    fi
}

restore_unique() {
    local file=$1
    case ":${RESTORED_FILES:-}:" in
        *":$file:"*) return 0 ;;
    esac
    RESTORED_FILES="${RESTORED_FILES:-}:$file"
    restore_one "$file"
}

if [[ $RESTORE_HOST == YES ]]; then
    restore_unique "$TNS_ADMIN/sqlnet.ora"
    restore_unique "$TNS_ADMIN/listener.ora"
    restore_unique "$TNS_ADMIN/tnsnames.ora"
fi

if [[ $RESTORE_CLIENT == YES ]]; then
    restore_unique "$TLS_CLIENT_TNS_ADMIN/sqlnet.ora"
    restore_unique "$TLS_CLIENT_TNS_ADMIN/tnsnames.ora"
fi

if [[ $RESTORE_HOST == YES ]]; then
    if ! "$LSNRCTL" reload "$TLS_LISTENER_NAME" >/dev/null 2>&1; then
        "$LSNRCTL" reload
    fi
    "$SQLPLUS" -s / as sysdba <<SQL
alter system register;
exit;
SQL
fi

printf '%s\n' 'TLS FastLab Oracle Net restore completed.'
printf 'Restore selector: %s\n' "$BACKUP_SELECTOR"
printf '%s\n' 'Current files were backed up before each restore. Wallets and certificates were not changed.'
