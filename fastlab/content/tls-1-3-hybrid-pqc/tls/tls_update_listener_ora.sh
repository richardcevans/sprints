#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

tls_init
LSNRCTL=$(tls_require_oracle_bin lsnrctl)
SQLPLUS=$(tls_require_oracle_bin sqlplus)
LISTENER_FILE="$TNS_ADMIN/listener.ora"
mkdir -p -- "$TNS_ADMIN" 2>/dev/null || tls_run_as_root mkdir -p -- "$TNS_ADMIN"
tls_touch_file "$LISTENER_FILE"
tls_backup_file "$LISTENER_FILE"

HAD_TCPS=0
if grep -Eiq 'PROTOCOL[[:space:]]*=[[:space:]]*TCPS' "$LISTENER_FILE"; then
    HAD_TCPS=1
else
    if ! grep -Eiq "^[[:space:]]*${TLS_LISTENER_NAME}[[:space:]]*=" "$LISTENER_FILE"; then
        while IFS= read -r line; do
            [[ -n $line ]] && tls_append_line "$LISTENER_FILE" "$line"
        done <<EOF

$TLS_LISTENER_NAME =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = $TLS_SERVER_HOST)(PORT = $TLS_TCP_PORT))
      (ADDRESS = (PROTOCOL = TCPS)(HOST = $TLS_SERVER_HOST)(PORT = $TLS_TCPS_PORT))
    )
  )
EOF
    fi
fi

tls_set_parameter "$LISTENER_FILE" SSL_CLIENT_AUTHENTICATION FALSE
if [[ ${TLS_CONFIGURE_TLS13:-YES} == YES ]]; then
    if [[ ${TLS_CRYPTO_PROVIDER:-} == legacy ]]; then
        tls_die 'TLS 1.3 and hybrid key exchange require the next-generation cryptographic provider on Oracle Database 19.32.'
    fi
    tls_set_parameter "$LISTENER_FILE" TLS_VERSION "(${TLS_VERSION_LIST})"
    tls_set_parameter "$LISTENER_FILE" TLS_KEY_EXCHANGE_GROUPS "$TLS_KEY_EXCHANGE_GROUPS"
fi

printf '%s\n' "Updated $LISTENER_FILE:"
cat -- "$LISTENER_FILE"
if (( HAD_TCPS == 1 )); then
    "$LSNRCTL" reload "${TLS_LISTENER_NAME}" 2>/dev/null || "$LSNRCTL" reload
else
    "$LSNRCTL" start "$TLS_LISTENER_NAME"
fi

"$SQLPLUS" -s / as sysdba <<SQL
alter system register;
exit;
SQL
