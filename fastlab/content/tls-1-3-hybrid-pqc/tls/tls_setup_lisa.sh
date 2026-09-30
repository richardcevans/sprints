#!/usr/bin/env bash
set -euo pipefail
umask 077
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
. /etc/os-release
[[ ${ID:-} == ol && ${VERSION_ID%%.*} =~ ^(8|9|10)$ ]] || {
    echo 'Task 3 requires Oracle Linux 8, 9, or 10.' >&2; exit 1;
}
PDB_NAME=${PDB_NAME:-pdb1}
[[ $PDB_NAME =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]] || { echo 'Invalid PDB name.' >&2; exit 1; }
base_alias=${TLS_TNS_ALIAS:-${PDB_NAME}_tls}
[[ $base_alias =~ ^[a-zA-Z][a-zA-Z0-9_.-]*$ ]] || { echo 'Invalid base alias.' >&2; exit 1; }
source_dir=${TNS_ADMIN:-${ORACLE_HOME:?Set ORACLE_HOME or TNS_ADMIN in the oracle shell.}/network/admin}
source_file=$source_dir/tnsnames.ora
[[ -r $source_file ]] || { echo "Cannot read $source_file" >&2; exit 1; }
[[ -s /etc/pki/tls/certs/ca-bundle.crt ]] || { echo 'System CA bundle missing; complete Task 2.' >&2; exit 1; }
# Read a simple, single-address TCPS base alias. Do not inherit wallet paths,
# IFILE directives, stale version aliases, or unrelated entries from the server.
fields=$(awk -v wanted="$base_alias" '
    !inside {
        name=$0; sub(/=.*/, "", name); gsub(/[[:space:]]/, "", name)
        if (tolower(name)==tolower(wanted) && index($0,"=")) inside=1
    }
    inside {
        original=$0; sub(/#.*/, "", original); line=tolower(original)
        if (line ~ /protocol[[:space:]]*=[[:space:]]*tcps/) tcps=1
        rest=line; addresses+=gsub(/\(address[[:space:]]*=/,"",rest)
        if (match(line,/host[[:space:]]*=[[:space:]]*[^ )]+/)) {
            host=substr(original,RSTART,RLENGTH); sub(/^[^=]*=[[:space:]]*/,"",host)
        }
        if (match(line,/port[[:space:]]*=[[:space:]]*[0-9]+/)) {
            port=substr(original,RSTART,RLENGTH); sub(/^[^=]*=[[:space:]]*/,"",port)
        }
        if (match(line,/service_name[[:space:]]*=[[:space:]]*[^ )]+/)) {
            service=substr(original,RSTART,RLENGTH); sub(/^[^=]*=[[:space:]]*/,"",service)
        }
        rest=original; opened=gsub(/\(/,"",rest); rest=original; closed=gsub(/\)/,"",rest)
        depth+=opened-closed; if(opened) seen=1
        if(seen && depth==0) { complete=1; exit }
    }
    END { if(complete && tcps && addresses==1 && host!="" && port!="" && service!="") print host "|" port "|" service; else exit 1 }
' "$source_file") || { echo "Cannot parse simple TCPS alias $base_alias in $source_file. Review the base alias." >&2; exit 1; }
IFS='|' read -r host port service <<< "$fields"
[[ $host =~ ^[a-zA-Z0-9_.:-]+$ && $service =~ ^[a-zA-Z0-9_.-]+$ ]] || { echo 'Unsupported host/service syntax.' >&2; exit 1; }
if [[ ${#port} -gt 5 ]] || (( 10#$port <= 0 || 10#$port > 65535 )); then
    echo 'Invalid port.' >&2
    exit 1
fi
if id lisa >/dev/null 2>&1; then
    [[ $(getent passwd lisa | cut -d: -f6) == /home/lisa ]] || { echo 'Lisa home must be /home/lisa; no changes made.' >&2; exit 1; }
fi
printf 'Non-production lab only. Configure Lisa for %s:%s/%s using system trust.\n' "$host" "$port" "$service"
# Check/install packages before creating the account or changing its files.
bash "$SCRIPT_DIR/tls_install_lisa_ic.sh"
if ! id lisa >/dev/null 2>&1; then sudo useradd -m -d /home/lisa -s /bin/bash lisa; fi
getent passwd lisa
[[ $(getent passwd lisa | cut -d: -f6) == /home/lisa ]] || { echo 'Unexpected Lisa home.' >&2; exit 1; }
group=$(id -gn lisa)
config_target=/home/lisa/tns_admin
lab_parent=/home/lisa/livelabs
lab_target=$lab_parent/tls
sudo test ! -L /home/lisa || { echo 'Refusing a symlinked home.' >&2; exit 1; }
sudo test ! -L "$config_target" || { echo 'Refusing a symlinked configuration directory.' >&2; exit 1; }
sudo test ! -L "$lab_parent" || { echo 'Refusing a symlinked livelabs directory.' >&2; exit 1; }
sudo test ! -L "$lab_target" || { echo 'Refusing a symlinked TLS lab directory.' >&2; exit 1; }
sudo install -d -o lisa -g "$group" -m 0750 "$config_target" "$lab_parent" "$lab_target"
# Retain existing configuration and scripts in unique backup directories on reruns.
config_backup=$(sudo mktemp -d "$config_target/before-task3.XXXXXX")
lab_backup=$(sudo mktemp -d "$lab_target/before-task3.XXXXXX")
for name in sqlnet.ora tnsnames.ora tls_test_lisa.sh tls_test_lisa.sql; do
    sudo test ! -L "$config_target/$name" || { echo "Refusing symlink: $config_target/$name" >&2; exit 1; }
    if sudo test -e "$config_target/$name"; then sudo cp -p -- "$config_target/$name" "$config_backup/"; fi
done
# Remove script copies installed in tns_admin by earlier lab versions after preserving them.
sudo rm -f -- "$config_target/tls_test_lisa.sh" "$config_target/tls_test_lisa.sql"
for name in tls_test_lisa.sh tls_test_lisa.sql pdb_name; do
    sudo test ! -L "$lab_target/$name" || { echo "Refusing symlink: $lab_target/$name" >&2; exit 1; }
    if sudo test -e "$lab_target/$name"; then sudo cp -p -- "$lab_target/$name" "$lab_backup/"; fi
done
stage=$(mktemp -d)
trap 'rm -f -- "$stage/sqlnet.ora" "$stage/tnsnames.ora" "$stage/pdb_name"; rmdir -- "$stage"' EXIT
printf '%s\n' "$PDB_NAME" > "$stage/pdb_name"
cat > "$stage/sqlnet.ora" <<'NET'
NAMES.DIRECTORY_PATH = (TNSNAMES)
TLS_CLIENT_AUTHENTICATION = FALSE
TLS_SERVER_DN_MATCH = YES
TLS_VERSION = (TLSv1.2,TLSv1.3)
NET
for version in 1.2 1.3; do
    suffix=${version/./}
    cat >> "$stage/tnsnames.ora" <<NET
${PDB_NAME}_tls${suffix} =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCPS)(HOST = $host)(PORT = $port))
    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = $service))
    (SECURITY =
      (TLS_VERSION = TLSv${version})
      (TLS_SERVER_DN_MATCH = YES)
      (WALLET_LOCATION = SYSTEM)
    )
  )
NET
done
for name in sqlnet.ora tnsnames.ora; do
    sudo install -o lisa -g "$group" -m 0640 "$stage/$name" "$config_target/$name"
done
sudo install -o lisa -g "$group" -m 0750 "$SCRIPT_DIR/tls_test_lisa.sh" "$lab_target/tls_test_lisa.sh"
sudo install -o lisa -g "$group" -m 0640 "$SCRIPT_DIR/tls_test_lisa.sql" "$lab_target/tls_test_lisa.sql"
sudo install -o lisa -g "$group" -m 0640 "$stage/pdb_name" "$lab_target/pdb_name"
printf 'Lisa configured without a client wallet.\n'
printf '  Lab scripts: %s\n' "$lab_target"
printf '  Oracle Net configuration: %s\n' "$config_target"
printf '  Backups: %s and %s\n' "$lab_backup" "$config_backup"
