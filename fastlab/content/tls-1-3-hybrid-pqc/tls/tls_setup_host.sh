#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

tls_init
LSNRCTL=$(tls_require_oracle_bin lsnrctl)
SQLPLUS=$(tls_require_oracle_bin sqlplus)
SQLNET_FILE="$TNS_ADMIN/sqlnet.ora"
LISTENER_FILE="$TNS_ADMIN/listener.ora"
TNSNAMES_FILE="$TNS_ADMIN/tnsnames.ora"

if [[ ${TLS_CONFIGURE_TLS13:-YES} == YES && ${TLS_CRYPTO_PROVIDER:-} == legacy ]]; then
    tls_die 'TLS 1.3 and hybrid key exchange require the next-generation cryptographic provider on Oracle Database 19.32.'
fi

# Back up every existing Oracle Net file before creating a directory or touching
# any of the files under ORACLE_HOME/ORACLE_BASE.
for file in "$SQLNET_FILE" "$LISTENER_FILE" "$TNSNAMES_FILE"; do
    tls_backup_file "$file"
done

mkdir -p -- "$TNS_ADMIN" 2>/dev/null || tls_run_as_root mkdir -p -- "$TNS_ADMIN"
for file in "$SQLNET_FILE" "$LISTENER_FILE" "$TNSNAMES_FILE"; do
    tls_touch_file "$file"
done

tls_set_parameter "$SQLNET_FILE" SSL_CLIENT_AUTHENTICATION FALSE
tls_set_parameter "$LISTENER_FILE" SSL_CLIENT_AUTHENTICATION FALSE
if [[ ${TLS_CONFIGURE_TLS13:-YES} == YES ]]; then
    tls_set_parameter "$SQLNET_FILE" TLS_VERSION "(${TLS_VERSION_LIST})"
    tls_set_parameter "$LISTENER_FILE" TLS_VERSION "(${TLS_VERSION_LIST})"
    if [[ ${TLS_CONFIGURE_HYBRID:-NO} == YES ]]; then
        tls_set_parameter "$SQLNET_FILE" TLS_KEY_EXCHANGE_GROUPS "$TLS_KEY_EXCHANGE_GROUPS"
        tls_set_parameter "$LISTENER_FILE" TLS_KEY_EXCHANGE_GROUPS "$TLS_KEY_EXCHANGE_GROUPS"
    else
        tls_edit_in_place "$SQLNET_FILE" -E '/^[[:space:]]*TLS_KEY_EXCHANGE_GROUPS[[:space:]]*=.*/d'
        tls_edit_in_place "$LISTENER_FILE" -E '/^[[:space:]]*TLS_KEY_EXCHANGE_GROUPS[[:space:]]*=.*/d'
    fi
fi

HAD_TCPS=0
ADDED_LISTENER=0
if grep -Eiq 'PROTOCOL[[:space:]]*=[[:space:]]*TCPS' "$LISTENER_FILE"; then
    HAD_TCPS=1
    EXISTING_TCPS_PORT=$(awk '
        {
            lowered = tolower($0)
            if (lowered ~ /protocol[[:space:]]*=[[:space:]]*tcps/) {
                in_tcps_address = 1
            }
            if (in_tcps_address && match(lowered, /port[[:space:]]*=[[:space:]]*[0-9]+/)) {
                port = substr(lowered, RSTART, RLENGTH)
                sub(/.*=[[:space:]]*/, "", port)
                print port
                exit
            }
        }
    ' "$LISTENER_FILE")
    if [[ -n $EXISTING_TCPS_PORT ]]; then
        TLS_TCPS_PORT=$EXISTING_TCPS_PORT
        printf 'Using existing TCPS listener port: %s\n' "$TLS_TCPS_PORT"
    else
        tls_warn "A TCPS address exists in $LISTENER_FILE, but its port could not be detected; using TLS_TCPS_PORT=$TLS_TCPS_PORT."
    fi
elif ! grep -Eiq "^[[:space:]]*${TLS_LISTENER_NAME}[[:space:]]*=" "$LISTENER_FILE"; then
    while IFS= read -r line; do
        [[ -n $line ]] && tls_append_raw_line "$LISTENER_FILE" "$line"
    done <<EOF

$TLS_LISTENER_NAME =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = $TLS_SERVER_HOST)(PORT = $TLS_TCP_PORT))
      (ADDRESS = (PROTOCOL = TCPS)(HOST = $TLS_SERVER_HOST)(PORT = $TLS_TCPS_PORT))
    )
  )
EOF
    ADDED_LISTENER=1
else
    tls_warn "${TLS_LISTENER_NAME} already exists but no TCPS address was found; review $LISTENER_FILE before testing."
fi

if grep -Eiq "^[[:space:]]*${TLS_TNS_ALIAS}[[:space:]]*=" "$TNSNAMES_FILE"; then
    printf '%s\n' "TNS alias already exists: $TLS_TNS_ALIAS"
else
    while IFS= read -r line; do
        [[ -n $line ]] && tls_append_raw_line "$TNSNAMES_FILE" "$line"
    done <<EOF

$TLS_TNS_ALIAS =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCPS)(HOST = $TLS_SERVER_HOST)(PORT = $TLS_TCPS_PORT))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = $TLS_SERVICE_NAME)
    )
EOF
    if [[ -n ${TLS_TNS_TLS_VERSION:-} ]]; then
        tls_append_raw_line "$TNSNAMES_FILE" "    (SECURITY = (TLS_VERSION = $TLS_TNS_TLS_VERSION))"
    fi
    tls_append_raw_line "$TNSNAMES_FILE" '  )'
fi

printf '%s\n' "Updated $SQLNET_FILE:"
cat -- "$SQLNET_FILE"
printf '%s\n' "Updated $LISTENER_FILE:"
cat -- "$LISTENER_FILE"
printf '%s\n' "Updated $TNSNAMES_FILE:"
tail -30 -- "$TNSNAMES_FILE"

if (( ADDED_LISTENER == 1 )); then
    "$LSNRCTL" start "$TLS_LISTENER_NAME"
elif (( HAD_TCPS == 1 )); then
    if ! "$LSNRCTL" reload "$TLS_LISTENER_NAME" >/dev/null 2>&1; then
        "$LSNRCTL" reload
    fi
fi

"$SQLPLUS" -s / as sysdba <<SQL
alter system register;
exit;
SQL
