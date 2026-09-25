#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./tls_common.sh
source "$SCRIPT_DIR/tls_common.sh"

tls_init

TNSNAMES_FILE="$TLS_CLIENT_TNS_ADMIN/tnsnames.ora"
TLS13_ALIAS="${PDB_NAME}_tls13"
TLS12_ALIAS="${PDB_NAME}_tls12"

if grep -Eiq "^[[:space:]]*${TLS13_ALIAS}[[:space:]]*=" "$TNSNAMES_FILE" 2>/dev/null ||
   grep -Eiq "^[[:space:]]*${TLS12_ALIAS}[[:space:]]*=" "$TNSNAMES_FILE" 2>/dev/null; then
    if grep -Eiq "^[[:space:]]*${TLS13_ALIAS}[[:space:]]*=" "$TNSNAMES_FILE" &&
       grep -Eiq "^[[:space:]]*${TLS12_ALIAS}[[:space:]]*=" "$TNSNAMES_FILE"; then
        printf 'Both TLS test aliases already exist in %s; leaving them unchanged.\n' "$TNSNAMES_FILE"
        exit 0
    fi
    tls_die "Only one version-specific alias exists in $TNSNAMES_FILE. Review the file and remove or complete the pair before rerunning this script."
fi

tls_require_file "$TNSNAMES_FILE"

source_fields=$(awk -v wanted="$TLS_TNS_ALIAS" '
    function paren_delta(line, opened, closed) {
        opened = gsub(/\(/, "", line)
        closed = gsub(/\)/, "", line)
        return opened - closed
    }
    BEGIN { IGNORECASE = 1 }
    !inside && $0 ~ "^[[:space:]]*" wanted "[[:space:]]*=" { inside = 1 }
    inside {
        line = tolower($0)
        if (line ~ /protocol[[:space:]]*=[[:space:]]*tcps/) protocol = "tcps"
        if (host == "" && match(line, /host[[:space:]]*=[[:space:]]*[^ )]+/)) {
            host = substr(line, RSTART, RLENGTH)
            sub(/^[^=]*=[[:space:]]*/, "", host)
        }
        if (port == "" && match(line, /port[[:space:]]*=[[:space:]]*[0-9]+/)) {
            port = substr(line, RSTART, RLENGTH)
            sub(/^[^=]*=[[:space:]]*/, "", port)
        }
        if (service == "" && match(line, /service_name[[:space:]]*=[[:space:]]*[^ )]+/)) {
            service = substr(line, RSTART, RLENGTH)
            sub(/^[^=]*=[[:space:]]*/, "", service)
        }
        depth += paren_delta($0)
        if (index($0, "(") > 0) saw_descriptor = 1
        if (saw_descriptor && depth <= 0) exit
    }
    END {
        if (protocol == "tcps" && host != "" && port != "" && service != "")
            print host "|" port "|" service
    }
' "$TNSNAMES_FILE")

if [[ -z $source_fields ]]; then
    tls_die "Could not read a TCPS host, port, and service from alias $TLS_TNS_ALIAS in $TNSNAMES_FILE. Run tls_setup_client.sh first and review its generated alias."
fi
IFS='|' read -r TLS_SERVER_HOST TLS_TCPS_PORT TLS_SERVICE_NAME <<< "$source_fields"

tls_backup_file "$TNSNAMES_FILE"

for version in 1.3 1.2; do
    alias_name="$PDB_NAME"
    if [[ $version == 1.3 ]]; then
        alias_name="${alias_name}_tls13"
        tns_version=TLSv1.3
    else
        alias_name="${alias_name}_tls12"
        tns_version=TLSv1.2
    fi
    while IFS= read -r line; do
        [[ -n $line ]] && tls_append_raw_line "$TNSNAMES_FILE" "$line"
    done <<EOF

$alias_name =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCPS)(HOST = $TLS_SERVER_HOST)(PORT = $TLS_TCPS_PORT))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = $TLS_SERVICE_NAME)
    )
    (SECURITY = (TLS_VERSION = $tns_version)(WALLET_LOCATION = SYSTEM)(TLS_SERVER_DN_MATCH = TRUE))
  )
EOF
    printf 'Created %s with TLS %s using %s:%s/%s\n' "$alias_name" "$version" "$TLS_SERVER_HOST" "$TLS_TCPS_PORT" "$TLS_SERVICE_NAME"
done

printf 'Updated %s\n' "$TNSNAMES_FILE"
