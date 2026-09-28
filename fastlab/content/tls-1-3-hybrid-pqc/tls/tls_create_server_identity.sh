#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

case ${1:-} in
    '') ;;
    --recreate)
        export TLS_RECREATE_IDENTITY=YES
        ;;
    --help|-h)
        printf 'Usage: %s [--recreate]\n' "${0##*/}"
        printf '%s\n' '  --recreate  Back up and replace the generated root CA and database wallets.'
        exit 0
        ;;
    *)
        printf 'Unknown option: %s\n' "$1" >&2
        printf 'Usage: %s [--recreate]\n' "${0##*/}" >&2
        exit 2
        ;;
esac
[[ $# -le 1 ]] || {
    printf 'Usage: %s [--recreate]\n' "${0##*/}" >&2
    exit 2
}

if ! IFS= read -rsp 'TLS wallet password: ' tls_password; then
    printf '\nUnable to read the TLS wallet password.\n' >&2
    exit 1
fi
printf '\n'
if ! IFS= read -rsp 'Confirm TLS wallet password: ' tls_password_confirm; then
    printf '\nUnable to read the TLS wallet password confirmation.\n' >&2
    exit 1
fi
printf '\n'

if [[ -z $tls_password ]]; then
    echo 'The TLS wallet password cannot be empty.' >&2
    exit 1
fi
if [[ $tls_password != "$tls_password_confirm" ]]; then
    echo 'The TLS wallet passwords do not match. No wallet changes were made.' >&2
    exit 1
fi

export TLS_PASSWORD=$tls_password
unset tls_password tls_password_confirm

steps=(
    tls_create_rootCA_wallet.sh
    tls_create_DB_wallet.sh
    tls_sign_DB_cert.sh
    tls_import_signed_cert.sh
)

for step in "${steps[@]}"; do
    [[ -x $SCRIPT_DIR/$step ]] || {
        echo "Required executable script not found: $SCRIPT_DIR/$step" >&2
        exit 1
    }
done

for step in "${steps[@]}"; do
    printf '\nRunning %s\n' "$step"
    "$SCRIPT_DIR/$step"
done

unset TLS_PASSWORD
unset TLS_RECREATE_IDENTITY
printf '\nDatabase server identity wallet created successfully.\n'
