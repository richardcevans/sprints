#!/usr/bin/env bash
set -euo pipefail
. /etc/os-release
OL_MAJOR=${VERSION_ID%%.*}
[[ ${ID:-} == ol && $OL_MAJOR =~ ^(8|9|10)$ ]] || {
    echo "Requires Oracle Linux 8, 9, or 10; found ${PRETTY_NAME:-unknown}." >&2; exit 1;
}
# Do not let an Oracle Database home SQL*Plus mask a missing Instant Client.
installed=$(rpm -qa --qf '%{NAME} %{VERSION}\n' | awk '$1 ~ /^oracle-instantclient/ && $1 !~ /^oracle-instantclient-release-/')
printf '%s\n' "${installed:-No Oracle Instant Client RPMs are installed.}"
if [[ -n $installed ]] && printf '%s\n' "$installed" | grep -Evq '^[^ ]+ 23\.'; then
    echo 'A different Instant Client major version is installed. Review its application dependencies before continuing.' >&2
    exit 1
fi
sudo dnf -v install -y "oracle-instantclient-release-26ai-el${OL_MAJOR}"
sudo dnf -v install -y oracle-instantclient-basic oracle-instantclient-sqlplus
rpm -q oracle-instantclient-basic oracle-instantclient-sqlplus
