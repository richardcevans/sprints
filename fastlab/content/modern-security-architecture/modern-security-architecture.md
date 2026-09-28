# How Do You Build a Modern Security Architecture with TLS 1.2, TLS 1.3, and Hybrid Post-Quantum Key Exchange?

## Introduction

Configure TLS 1.2 and TLS 1.3 on Oracle AI Database 19.32 or Oracle AI Database 26ai. Prefer hybrid key exchange for TLS 1.3 when the selected release, provider, and both endpoints support it. Verify both versions over TCPS and separate key establishment from the record cipher.

Estimated Time: 15 minutes

Before changing configuration, confirm that this is a disposable, non-production system.

The lab requires the exact acknowledgement `NON_PROD_TLS_ACCEPTANCE=YES`. Type the acknowledgement manually; this lab intentionally does not provide a Copy button for it.

```bash
export NON_PROD_TLS_ACCEPTANCE=YES
```

For a persistent setting, type these lines manually to add it to `.bashrc` and reload the shell:

```bash
echo 'export NON_PROD_TLS_ACCEPTANCE=YES' >> ~/.bashrc
source ~/.bashrc
```

For the current shell only, type:

```bash
export NON_PROD_TLS_ACCEPTANCE=YES
```

Before you begin, set `PDB_NAME` in the shell used for this lab. The commands use it for the database service and generated TNS aliases. If it is not set, the commands use `pdb1`.

For a persistent setting, add it to `.bashrc` and reload the shell:

```bash
<copy>
echo 'export PDB_NAME=pdb1' >> ~/.bashrc
source ~/.bashrc
</copy>
```

For the current shell only, run:

```bash
<copy>
export PDB_NAME=pdb1
</copy>
```

### Objectives

In this lab, you will:

- Configure `TLS_VERSION` to permit both TLS 1.2 and TLS 1.3.
- Configure `TLS_KEY_EXCHANGE_GROUPS` with hybrid key exchange preferred.
- Test TLS 1.3 and TLS 1.2 connections through the same TCPS endpoint.
- Verify the network protocol, negotiated TLS version, and cipher suite with `SYS_CONTEXT`.

### Prerequisites

This lab assumes you have:

- An Oracle AI Database 19.32 or Oracle AI Database 26ai server and a matching client with TLS 1.3 support.
- An existing one-way TLS configuration with a server certificate, trusted client certificate chain, and wallets available to the Oracle listener.
- OS access to the database host and client configuration files as the appropriate Oracle software owner.
- A working TCPS alias based on `PDB_NAME`, such as `${PDB_NAME}_tls`, plus database credentials for the lab PDB.

**Version-specific provider note:** On Oracle Database 19.32, TLS 1.3, ML-KEM, and hybrid key exchange require the next-generation cryptographic provider. The legacy provider remains the default on 19.32 and supports TLS only through 1.2, so it cannot use TLS 1.3 settings or `TLS_KEY_EXCHANGE_GROUPS` values that depend on TLS 1.3. Before Task 2, switch providers and restart. See the [Oracle Database 19c documentation on switching cryptographic providers](https://docs.oracle.com/en/database/oracle/oracle-database/19/dbseg/switching-crypto-providers.html):

```bash
<copy>
python $ORACLE_HOME/bin/set_crypto_provider.py next-generation
</copy>
```

Restart the database instance and reload the listener after the switch. Confirm the provider is active before proceeding to Task 2:

```bash
<copy>
python $ORACLE_HOME/bin/set_crypto_provider.py status
</copy>
```

This FastLab changes protocol and key-exchange settings and adds or updates the TCPS listener endpoint. It does not create wallets or certificates.
If the one-way TLS wallets and certificates are not configured, complete the [Oracle one-way TLS workshop](https://livelabs.oracle.com/ords/r/dbpm/livelabs/view-workshop?wid=3631).

## Task 1: Prepare the host and confirm prerequisites

Open a Terminal session on your **DBSec-Lab** VM as OS user `oracle`. This FastLab changes Oracle Net configuration and restarts a listener, so use a disposable non-production system.

1. Confirm the acknowledgement and identify the database environment.

    ```bash
    <copy>
    export NON_PROD_TLS_ACCEPTANCE=YES
    test -n "${ORACLE_HOME:-}" || { echo "Set ORACLE_HOME before continuing."; exit 1; }
    export PDB_NAME=${PDB_NAME:-pdb1}
    export TNS_ADMIN=${TNS_ADMIN:-$ORACLE_HOME/network/admin}
    export ORACLE_BASE=${ORACLE_BASE:-$(cd "$ORACLE_HOME/../../.." && pwd)}
    export ORACLE_SID=${ORACLE_SID:-oracle}
    export WALLET_ROOT=${WALLET_ROOT:-$ORACLE_BASE/admin/$ORACLE_SID/wallet}
    export TLS_LISTENER_WALLET_DIR=${TLS_LISTENER_WALLET_DIR:-$WALLET_ROOT}
    export TLS_SERVER_HOST=${TLS_SERVER_HOST:-$(hostname -f 2>/dev/null || hostname)}
    export TLS_TCP_PORT=${TLS_TCP_PORT:-1521}
    export TLS_TCPS_PORT=${TLS_TCPS_PORT:-2484}
    export TLS_SERVICE_NAME=${TLS_SERVICE_NAME:-$PDB_NAME}
    export TLS_LISTENER_NAME=${TLS_LISTENER_NAME:-LISTENER}
    export TLS_TNS_ALIAS=${TLS_TNS_ALIAS:-${PDB_NAME}_tls}
    export TLS_VERSION_LIST=${TLS_VERSION_LIST:-TLSv1.2,TLSv1.3}
    export TLS_KEY_EXCHANGE_GROUPS=${TLS_KEY_EXCHANGE_GROUPS:-hybrid,ec}

    echo "PDB_NAME=$PDB_NAME"
    echo "ORACLE_HOME=$ORACLE_HOME"
    echo "TNS_ADMIN=$TNS_ADMIN"
    echo "TLS_SERVER_HOST=$TLS_SERVER_HOST"
    echo "TLS_TCPS_PORT=$TLS_TCPS_PORT"
    echo "TLS_SERVICE_NAME=$TLS_SERVICE_NAME"
    </copy>
    ```

    Set `ORACLE_HOME`, `ORACLE_SID`, and `TNS_ADMIN` explicitly if the host has more than one database or Oracle home.

2. Confirm the operating system and required Oracle tools.

    ```bash
    <copy>
    . /etc/os-release
    case "${ID:-}" in
        ol) echo "Oracle Linux $VERSION_ID detected." ;;
        *) echo "This FastLab targets Oracle Linux; detected ${PRETTY_NAME:-unknown}."; exit 1 ;;
    esac
    command -v sqlplus
    command -v lsnrctl
    command -v openssl
    </copy>
    ```

3. Confirm that the existing one-way TLS configuration is present. This FastLab does not create wallets, certificates, or private keys.

    ```bash
    <copy>
    test -d "$TLS_LISTENER_WALLET_DIR" || { echo "Listener wallet directory is missing: $TLS_LISTENER_WALLET_DIR"; exit 1; }
    test -f "$TLS_LISTENER_WALLET_DIR/cwallet.sso" || test -f "$TLS_LISTENER_WALLET_DIR/ewallet.p12" || {
        echo "No listener wallet was found in $TLS_LISTENER_WALLET_DIR."
        exit 1
    }
    ls -l "$TLS_LISTENER_WALLET_DIR"
    </copy>
    ```

    If the wallet and certificate configuration is not ready, complete the [Oracle one-way TLS workshop](https://livelabs.oracle.com/ords/r/dbpm/livelabs/view-workshop?wid=3631) first.

## Task 2: Configure TLS 1.2 and TLS 1.3 on the host

Run these commands on the database host as the Oracle software owner. They preserve backups of the existing Oracle Net files, configure TLS 1.2 and TLS 1.3, create a TCPS alias named `${PDB_NAME}_tls`, and add a TCPS listener endpoint when one is not already present.

The database server and listener require the existing identity wallet. The client uses the Oracle Linux system trust store, not a client wallet.

1. Back up the current Oracle Net files and listener wallet directory.

    ```bash
    <copy>
    for file in "$TNS_ADMIN/sqlnet.ora" "$TNS_ADMIN/listener.ora" "$TNS_ADMIN/tnsnames.ora"; do
        if [[ -e "$file" ]]; then
            backup="${file}.before-tls-fastlab"
            [[ -e "$backup" ]] && backup="${file}.before-tls-fastlab.$(date +%Y%m%d%H%M%S)"
            cp -p -- "$file" "$backup"
            echo "Backup: $backup"
        fi
    done

    if [[ -d "$TLS_LISTENER_WALLET_DIR" ]]; then
        backup="${TLS_LISTENER_WALLET_DIR}.before-tls-fastlab"
        [[ -e "$backup" ]] && backup="${TLS_LISTENER_WALLET_DIR}.before-tls-fastlab.$(date +%Y%m%d%H%M%S)"
        cp -a -- "$TLS_LISTENER_WALLET_DIR" "$backup"
        echo "Directory backup: $backup"
    fi
    </copy>
    ```

2. Configure server and listener TLS parameters. Hybrid key exchange remains disabled until Task 4.

    ```bash
    <copy>
    mkdir -p "$TNS_ADMIN"
    touch "$TNS_ADMIN/sqlnet.ora" "$TNS_ADMIN/listener.ora" "$TNS_ADMIN/tnsnames.ora"

    for file in "$TNS_ADMIN/sqlnet.ora" "$TNS_ADMIN/listener.ora"; do
        sed -i -E "/^[[:space:]]*(SSL_CLIENT_AUTHENTICATION|TLS_VERSION|TLS_KEY_EXCHANGE_GROUPS)[[:space:]]*=/d" "$file"
        {
            echo "SSL_CLIENT_AUTHENTICATION = FALSE"
            echo "TLS_VERSION = (TLSv1.2,TLSv1.3)"
        } >> "$file"
    done

    sed -i -E "/^[[:space:]]*WALLET_LOCATION[[:space:]]*=/d" "$TNS_ADMIN/listener.ora"
    echo "WALLET_LOCATION = (SOURCE = (METHOD = FILE) (METHOD_DATA = (DIRECTORY = $TLS_LISTENER_WALLET_DIR)))" >> "$TNS_ADMIN/listener.ora"
    </copy>
    ```

3. Confirm the TCPS listener port. Keep an existing port if one is already configured; otherwise use the recommended port 2484.

    ```bash
    <copy>
    grep -n -i -E "PROTOCOL[[:space:]]*=[[:space:]]*TCPS|PORT[[:space:]]*=" "$TNS_ADMIN/listener.ora"
    export TLS_TCPS_PORT=2484
    echo "Set TLS_TCPS_PORT to the existing TCPS port if the previous command showed a different port."
    </copy>
    ```

    If no TCPS address exists, add one. If the named listener already has a TCP address, the first branch inserts the TCPS address beside it. Otherwise, the second branch creates a listener descriptor.

    ```bash
    <copy>
    if ! grep -Eiq "PROTOCOL[[:space:]]*=[[:space:]]*TCPS" "$TNS_ADMIN/listener.ora"; then
        if grep -Eiq "^[[:space:]]*${TLS_LISTENER_NAME}[[:space:]]*=" "$TNS_ADMIN/listener.ora"; then
            sed -i -E "/PROTOCOL[[:space:]]*=[[:space:]]*TCP[)]/a\      (ADDRESS = (PROTOCOL = TCPS)(HOST = ${TLS_SERVER_HOST})(PORT = ${TLS_TCPS_PORT}))" "$TNS_ADMIN/listener.ora"
        else
            cat >> "$TNS_ADMIN/listener.ora" <<EOF
${TLS_LISTENER_NAME} =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = ${TLS_SERVER_HOST})(PORT = ${TLS_TCP_PORT}))
      (ADDRESS = (PROTOCOL = TCPS)(HOST = ${TLS_SERVER_HOST})(PORT = ${TLS_TCPS_PORT}))
    )
  )
EOF
        fi
    fi
    </copy>
    ```

4. Add the base TCPS alias if it does not already exist.

    ```bash
    <copy>
    if ! grep -Eiq "^[[:space:]]*${TLS_TNS_ALIAS}[[:space:]]*=" "$TNS_ADMIN/tnsnames.ora"; then
        cat >> "$TNS_ADMIN/tnsnames.ora" <<EOF
${TLS_TNS_ALIAS} =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCPS)(HOST = ${TLS_SERVER_HOST})(PORT = ${TLS_TCPS_PORT}))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ${TLS_SERVICE_NAME})
    )
  )
EOF
    fi
    </copy>
    ```

5. If the server uses a private CA that is not trusted by Oracle Linux, install only the issuer public root certificate. Skip this step when the issuer is already trusted.

    ```bash
    <copy>
    export TLS_ROOT_CERT=/path/to/server-issuing-root-ca.pem
    openssl x509 -in "$TLS_ROOT_CERT" -noout -subject -issuer
    openssl x509 -in "$TLS_ROOT_CERT" -noout -text | grep -q "CA:TRUE"
    sudo install -v -o root -g root -m 0644 "$TLS_ROOT_CERT" /etc/pki/ca-trust/source/anchors/tls-fastlab-root-ca.crt
    sudo update-ca-trust extract
    </copy>
    ```

6. Configure the oracle client to use the operating-system trust store.

    ```bash
    <copy>
    sed -i -E "/^[[:space:]]*WALLET_LOCATION[[:space:]]*=/d" "$TNS_ADMIN/sqlnet.ora"
    sed -i -E "/^[[:space:]]*(SSL_CLIENT_AUTHENTICATION|TLS_VERSION|TLS_KEY_EXCHANGE_GROUPS)[[:space:]]*=/d" "$TNS_ADMIN/sqlnet.ora"
    {
        echo "SSL_CLIENT_AUTHENTICATION = FALSE"
        echo "TLS_VERSION = (TLSv1.2,TLSv1.3)"
    } >> "$TNS_ADMIN/sqlnet.ora"
    </copy>
    ```

7. Restart the listener and register the database services.

    ```bash
    <copy>
    lsnrctl stop "$TLS_LISTENER_NAME" >/dev/null 2>&1 || true
    lsnrctl start "$TLS_LISTENER_NAME"
    sqlplus -s / as sysdba <<SQL
    alter system register;
    exit;
    SQL
    </copy>
    ```

8. Review the effective host configuration.

    ```bash
    <copy>
    grep -Ei "^[[:space:]]*(SSL_CLIENT_AUTHENTICATION|TLS_VERSION|TLS_KEY_EXCHANGE_GROUPS|WALLET_LOCATION)[[:space:]]*=" "$TNS_ADMIN/sqlnet.ora" "$TNS_ADMIN/listener.ora"
    grep -A8 -B1 -E "^[[:space:]]*${TLS_TNS_ALIAS}[[:space:]]*=" "$TNS_ADMIN/tnsnames.ora"
    </copy>
    ```

### Inspect the TLS connection as `oracle`

Connect through the `${PDB_NAME}_tls` alias and record the protocol, negotiated TLS version, and record-layer cipher suite.

1. Connect with the generated TCPS alias as the `system` user and enter its password when prompted.

    ```bash
    <copy>
    sqlplus "system@${PDB_NAME}_tls"
    </copy>
    ```

2. Verify the connection values.

    ```sql
    <copy>
    SELECT SYS_CONTEXT('USERENV', 'NETWORK_PROTOCOL') AS network_protocol,
           SYS_CONTEXT('USERENV', 'TLS_VERSION') AS tls_version,
           SYS_CONTEXT('USERENV', 'TLS_CIPHERSUITE') AS tls_ciphersuite
      FROM dual;
    </copy>
    ```

    `NETWORK_PROTOCOL` should be `tcps`.

3. Exit SQL*Plus to return to the command line before continuing to the next task.

    ```sql
    <copy>
    exit
    </copy>
    ```

## Task 3: Create and prepare the Lisa client

Create a separate Linux login and use Oracle Instant Client 26ai to test the two TCPS aliases. The CA root was added to the host-wide Oracle Linux trust store in Task 2; Lisa does not receive or use a client wallet.

1. Create Lisa if this account does not already exist.

    ```bash
    <copy>
    if ! id lisa >/dev/null 2>&1; then
        sudo useradd -m -s /bin/bash lisa
    fi
    getent passwd lisa
    </copy>
    ```

    Confirm that Lisa home directory is /home/lisa before continuing.

2. Check for an existing Instant Client RPM, then install the 26ai repository and SQL*Plus packages.

    ```bash
    <copy>
    . /etc/os-release
    OL_MAJOR=$(echo "$VERSION_ID" | cut -d. -f1)
    case "$OL_MAJOR" in
        8|9|10) ;;
        *) echo "Unsupported Oracle Linux release: $VERSION_ID"; exit 1 ;;
    esac

    sudo dnf -v list installed "oracle-instantclient*" || true
    sudo dnf -v install -y "oracle-instantclient-release-26ai-el$OL_MAJOR"
    sudo dnf -v install -y oracle-instantclient-basic oracle-instantclient-sqlplus
    </copy>
    ```

    Oracle Instant Client RPM installs one major version at a time. If another Instant Client RPM is already installed, do not remove or replace it without checking whether another application depends on it.

3. Create Lisa Oracle Net files and copy the base TCPS alias.

    ```bash
    <copy>
    export LISA_TNS_ADMIN=/home/lisa/tns_admin
    export ORACLE_NET_ADMIN=$TNS_ADMIN

    sudo install -v -d -o lisa -g lisa -m 0750 "$LISA_TNS_ADMIN"
    sudo install -v -o lisa -g lisa -m 0640 "$ORACLE_NET_ADMIN/tnsnames.ora" "$LISA_TNS_ADMIN/tnsnames.ora"

    sudo tee "$LISA_TNS_ADMIN/sqlnet.ora" >/dev/null <<EOF
SSL_CLIENT_AUTHENTICATION = FALSE
TLS_VERSION = (TLSv1.2,TLSv1.3)
EOF

    sudo chown -Rv lisa:lisa "$LISA_TNS_ADMIN"
    grep -A8 -B1 -E "^[[:space:]]*${TLS_TNS_ALIAS}[[:space:]]*=" "$LISA_TNS_ADMIN/tnsnames.ora"
    </copy>
    ```

    The client file omits `WALLET_LOCATION`, so Oracle Instant Client uses the operating-system trust store. No server wallet or private key is copied to Lisa.

4. Switch to the Lisa login and set the client environment.

    ```bash
    <copy>
    sudo su - lisa
    </copy>
    ```

    Run the following commands in the Lisa login shell. A login shell does not inherit `PDB_NAME` from oracle.

    ```bash
    <copy>
    export PDB_NAME=pdb1
    export TNS_ADMIN=/home/lisa/tns_admin
    export PATH=/usr/lib/oracle/26/client64/bin:$PATH
    sqlplus -v
    </copy>
    ```

5. Return to the oracle shell.

    ```bash
    <copy>
    exit
    </copy>
    ```

## Task 4: Prefer hybrid key exchange

`TLS_KEY_EXCHANGE_GROUPS` controls key-establishment groups. The hybrid group combines ML-KEM and ECDHE into one shared secret. It changes key establishment, not the record cipher shown by `TLS_CIPHERSUITE`.

1. Add hybrid preference to the database host and listener configuration.

    ```bash
    <copy>
    export TLS_KEY_EXCHANGE_GROUPS=hybrid,ec

    for file in "$TNS_ADMIN/sqlnet.ora" "$TNS_ADMIN/listener.ora"; do
        sed -i -E "/^[[:space:]]*TLS_KEY_EXCHANGE_GROUPS[[:space:]]*=/d" "$file"
        echo "TLS_KEY_EXCHANGE_GROUPS = ($TLS_KEY_EXCHANGE_GROUPS)" >> "$file"
    done

    lsnrctl stop "$TLS_LISTENER_NAME" >/dev/null 2>&1 || true
    lsnrctl start "$TLS_LISTENER_NAME"
    sqlplus -s / as sysdba <<SQL
    alter system register;
    exit;
    SQL
    </copy>
    ```

2. Add the same preference to the oracle and Lisa clients.

    ```bash
    <copy>
    sed -i -E "/^[[:space:]]*TLS_KEY_EXCHANGE_GROUPS[[:space:]]*=/d" "$TNS_ADMIN/sqlnet.ora"
    echo "TLS_KEY_EXCHANGE_GROUPS = ($TLS_KEY_EXCHANGE_GROUPS)" >> "$TNS_ADMIN/sqlnet.ora"

    sudo sed -i -E "/^[[:space:]]*TLS_KEY_EXCHANGE_GROUPS[[:space:]]*=/d" /home/lisa/tns_admin/sqlnet.ora
    echo "TLS_KEY_EXCHANGE_GROUPS = ($TLS_KEY_EXCHANGE_GROUPS)" | sudo tee -a /home/lisa/tns_admin/sqlnet.ora >/dev/null
    </copy>
    ```

    The hybrid group is listed first so endpoints that support hybrid post-quantum key exchange prefer it. The ec group provides a classical ECDHE fallback. ML-KEM and hybrid key exchange apply only to TLS 1.3.

3. Review the effective settings.

    ```bash
    <copy>
    grep -Ei "^[[:space:]]*(TLS_VERSION|TLS_KEY_EXCHANGE_GROUPS)[[:space:]]*=" "$TNS_ADMIN/sqlnet.ora" "$TNS_ADMIN/listener.ora" /home/lisa/tns_admin/sqlnet.ora
    </copy>
    ```

The SQL context does not expose the negotiated group; the `TLS_CIPHERSUITE` value is not proof of hybrid key exchange.

## Task 5: Create version-specific aliases and verify both protocols

Create two client aliases that use the same TCPS endpoint but request a specific TLS version. Then connect through each alias and compare the session context values.

1. Return to the oracle shell if necessary and create the TLS 1.3 and TLS 1.2 aliases in Lisa Oracle Net configuration.

    ```bash
    <copy>
    export LISA_TNS_ADMIN=/home/lisa/tns_admin
    export TLS13_ALIAS=${PDB_NAME}_tls13
    export TLS12_ALIAS=${PDB_NAME}_tls12

    sudo cp -p "$LISA_TNS_ADMIN/tnsnames.ora" "$LISA_TNS_ADMIN/tnsnames.ora.before-tls-fastlab"

    if ! grep -Eiq "^[[:space:]]*${TLS13_ALIAS}[[:space:]]*=" "$LISA_TNS_ADMIN/tnsnames.ora"; then
        sudo tee -a "$LISA_TNS_ADMIN/tnsnames.ora" >/dev/null <<EOF
$TLS13_ALIAS =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCPS)(HOST = $TLS_SERVER_HOST)(PORT = $TLS_TCPS_PORT))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = $TLS_SERVICE_NAME)
    )
    (SECURITY = (TLS_VERSION = TLSv1.3)(WALLET_LOCATION = SYSTEM)(TLS_SERVER_DN_MATCH = YES))
  )
EOF
    fi

    if ! grep -Eiq "^[[:space:]]*${TLS12_ALIAS}[[:space:]]*=" "$LISA_TNS_ADMIN/tnsnames.ora"; then
        sudo tee -a "$LISA_TNS_ADMIN/tnsnames.ora" >/dev/null <<EOF
$TLS12_ALIAS =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCPS)(HOST = $TLS_SERVER_HOST)(PORT = $TLS_TCPS_PORT))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = $TLS_SERVICE_NAME)
    )
    (SECURITY = (TLS_VERSION = TLSv1.2)(WALLET_LOCATION = SYSTEM)(TLS_SERVER_DN_MATCH = YES))
  )
EOF
    fi

    sudo chown -Rv lisa:lisa "$LISA_TNS_ADMIN"
    grep -A9 -B1 -E "^[[:space:]]*($TLS13_ALIAS|$TLS12_ALIAS)[[:space:]]*=" "$LISA_TNS_ADMIN/tnsnames.ora"
    </copy>
    ```

2. Switch to Lisa and test TLS 1.3.

    ```bash
    <copy>
    sudo su - lisa
    export PDB_NAME=pdb1
    export TNS_ADMIN=/home/lisa/tns_admin
    export PATH=/usr/lib/oracle/26/client64/bin:$PATH
    sqlplus "system@${PDB_NAME}_tls13"
    </copy>
    ```

    At the SQL prompt, run the session query from Task 2 and then enter exit. The result should show `NETWORK_PROTOCOL`=tcps and `TLS_VERSION`=TLSv1.3.

3. Test TLS 1.2 from the same Lisa login.

    ```bash
    <copy>
    sqlplus "system@${PDB_NAME}_tls12"
    </copy>
    ```

    Run the same session query and enter exit. The result should show `NETWORK_PROTOCOL`=tcps and `TLS_VERSION`=TLSv1.2. This connection demonstrates backward compatibility; it does not use ML-KEM or hybrid key exchange.

4. Return to the oracle shell.

    ```bash
    <copy>
    exit
    </copy>
    ```

### Interpret the results

- `NETWORK_PROTOCOL`=tcps confirms that the database session uses Transport Layer Security.
- `TLS_VERSION` confirms which protocol version the endpoints negotiated.
- `TLS_CIPHERSUITE` identifies the record-layer authentication, encryption, and integrity algorithms. It does not identify the key-exchange group.

For either supported release, hybrid is the configured TLS 1.3 preference when the selected provider and both endpoints support it. On Oracle Database 19.32, this requires the next-generation provider. The SQL context does not expose the negotiated group, so cipher output is not proof of hybrid key exchange.

If TLS 1.3 fails, confirm the selected release and provider, confirm hybrid support on both endpoints, reload the listener, and check that Lisa uses /home/lisa/`tns_admin`.

### Optional rollback

Restore the Oracle Net files from the backups made before the lab. The commands back up the current files first, restore the host and Lisa client configuration, and re-register database services. They do not change wallets or certificates.

1. Restore the host files.

    ```bash
    <copy>
    for file in "$TNS_ADMIN/sqlnet.ora" "$TNS_ADMIN/listener.ora" "$TNS_ADMIN/tnsnames.ora"; do
        backup="${file}.before-tls-fastlab"
        if [[ -f "$backup" ]]; then
            cp -p -- "$file" "${file}.before-tls-fastlab.current" 2>/dev/null || true
            cp -p -- "$backup" "$file"
        fi
    done
    </copy>
    ```

2. Restore Lisa client files and restart the listener.

    ```bash
    <copy>
    for file in /home/lisa/tns_admin/sqlnet.ora /home/lisa/tns_admin/tnsnames.ora; do
        backup="${file}.before-tls-fastlab"
        if [[ -f "$backup" ]]; then
            sudo cp -p -- "$file" "${file}.before-tls-fastlab.current" 2>/dev/null || true
            sudo cp -p -- "$backup" "$file"
        fi
    done

    lsnrctl stop "$TLS_LISTENER_NAME" >/dev/null 2>&1 || true
    lsnrctl start "$TLS_LISTENER_NAME"
    sqlplus -s / as sysdba <<SQL
    alter system register;
    exit;
    SQL
    </copy>
    ```

You may now proceed to the next lab.

## Signature Workshop

Ready to dive deeper? These workshops move from TLS setup to a complete encrypted database connection.

👉 [Successfully protect your database communication using 1-way Transport Layer Security (TLS)](https://livelabs.oracle.com/ords/r/dbpm/livelabs/view-workshop?wid=3631)

## Learn More

- [Oracle AI Database 26ai Security Guide: Transport Layer Security](https://docs.oracle.com/en/database/oracle/oracle-database/26/dbseg/configuring-transport-layer-security-encryption.html)
- [Oracle AI Database 26ai Net Services Reference: `sqlnet.ora` Parameters](https://docs.oracle.com/en/database/oracle/oracle-database/26/netrf/parameters-for-the-sqlnet.ora.html)
- [Oracle Database 19c Security Guide: Transport Layer Security](https://docs.oracle.com/en/database/oracle/oracle-database/19/dbseg/configuring-transport-layer-security-encryption.html)
- [Oracle Database 19c Net Services Reference: `sqlnet.ora` Parameters](https://docs.oracle.com/en/database/oracle/oracle-database/19/netrf/parameters-for-the-sqlnet.ora.html)
- [Oracle Database 19c Now Supports TLS 1.3, Post-Quantum Cryptography, and FIPS 140-3 Mode](https://blogs.oracle.com/database/database-19c-now-supports-tls-1-3-post-quantum-cryptography)
- [Both is better - Oracle AI Database 26ai adds hybrid-mode quantum-resistant support](https://blogs.oracle.com/database/hybrid-pqc)
- [Announcing support for TLS 1.3 in Oracle Database 23ai](https://blogs.oracle.com/database/announcing-tls13)
- [Oracle AI Database walletless TLS](https://www.braddiggs.com/2026/08/oracle-ai-database-walletless-tls.html) (community article)

## Acknowledgements

- **Author** - Richard C. Evans
- **Last Updated By/Date** - Richard C. Evans, September 2026
- **Technical references** - Oracle Database Security documentation and Oracle Database Insider articles listed above
