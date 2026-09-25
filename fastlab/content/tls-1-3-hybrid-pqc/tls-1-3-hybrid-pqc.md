# How Do You Configure TLS 1.2 and TLS 1.3 with Hybrid Post-Quantum Key Exchange?

## Introduction

Configure TLS 1.2 and TLS 1.3 on Oracle AI Database 19.32 or Oracle AI Database 26ai. Prefer hybrid key exchange for TLS 1.3 when the selected release, provider, and both endpoints support it. Verify both versions over TCPS and separate key establishment from the record cipher.

Estimated Time: 15 minutes

Before running any script, confirm that this is a disposable, non-production system.

The scripts require the exact acknowledgement `NON_PROD_TLS_ACCEPTANCE=YES`. Type the acknowledgement manually; this lab intentionally does not provide a Copy button for it.

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

Before you begin, set `PDB_NAME` in the shell used for this lab. The scripts use it for the database service and generated TNS aliases. If it is not set, the scripts default to `pdb1`.

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

## Task 1: Download and prepare the TLS scripts

Open a Terminal session on your **DBSec-Lab** VM as OS user `oracle`. The archive contains only the `tls/` directory and its scripts.

1. Create the `livelabs` directory and move into it.

    ```bash
    <copy>
    mkdir -pv livelabs
    cd livelabs
    </copy>
    ```

    If you are using a remote desktop session, double-click the **Terminal** icon on the desktop.

2. Download the bundled TLS scripts.

    ```bash
    <copy>
    wget -v -O tls.zip https://objectstorage.us-ashburn-1.oraclecloud.com/p/BHNwcP7_8g6cj9ap6j8r3rjBky44eNnrTsm8SGQ4jijQWWzjb4pMAnuiXxS1KQ8q/n/oradbclouducm/b/dbsec_public/o/tls.zip
    </copy>
    ```

3. Extract the archive and remove the downloaded ZIP.

    ```bash
    <copy>
    unzip tls.zip
    rm -vf tls.zip
    </copy>
    ```

4. Enter the extracted `tls` directory and prepare the scripts.

    ```bash
    <copy>
    cd tls
    chmod -v +x -- *.sh
    if command -v dos2unix >/dev/null 2>&1; then dos2unix -v -- *; else echo "dos2unix is not installed; the bundled scripts already use Unix line endings."; fi
    </copy>
    ```

## Task 2: Configure TLS 1.2 and TLS 1.3 on the host

Run these scripts from the extracted `livelabs/tls` directory on the database host as the Oracle software owner. Before writing, they make timestamped backups of the existing Oracle Net files and wallet directories, configure TLS 1.2 and TLS 1.3, create a TCPS alias named `${PDB_NAME}_tls`, and add or update the TCPS listener endpoint. They use Oracle's recommended TCPS port `2484` when adding a new endpoint and reuse an existing TCPS listener port when one is already configured. They do not create or modify wallets or certificates.

By default, the host setup restarts the listener so new TCPS endpoints and wallet settings take effect. The listener wallet path is `${WALLET_ROOT}`; set `TLS_LISTENER_WALLET_DIR` when the existing listener wallet is elsewhere.

The client setup writes `WALLET_LOCATION` to `sqlnet.ora` so the client can validate the server certificate. On the database host it defaults to the existing listener wallet. On a separate client host, set `TLS_CLIENT_WALLET_DIR` to that host's existing client trust wallet before running `tls_setup_client.sh`.

1. Confirm the variables and Oracle Net locations.

    ```bash
    <copy>
    echo "PDB_NAME=$PDB_NAME"
    echo "ORACLE_HOME=$ORACLE_HOME"
    echo "TNS_ADMIN=${TNS_ADMIN:-$ORACLE_HOME/network/admin}"
    </copy>
    ```

    If `/etc/oratab` contains multiple database entries for the same `ORACLE_HOME`, set both `ORACLE_HOME` and `ORACLE_SID` explicitly. The scripts stop rather than guess which database to change.

2. Configure TLS 1.2 and TLS 1.3. Hybrid key exchange remains disabled until Task 4.

    ```bash
    <copy>
    export TLS_CONFIGURE_TLS13=YES
    export TLS_CONFIGURE_HYBRID=NO
    ./tls_setup_host.sh
    </copy>
    ```

    If the client uses a separate host, run the combined client setup script there after setting the same `PDB_NAME` and `TNS_ADMIN`:

    ```bash
    <copy>
    export TLS_CLIENT_WALLET_DIR="${TLS_CLIENT_WALLET_DIR:-$WALLET_ROOT}"
    ./tls_setup_client.sh
    </copy>
    ```

3. Confirm the host configuration and generated alias.

    ```bash
    <copy>
    ./tls_verify_host.sh
    </copy>
    ```

## Task 3: Inspect the TLS connection

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

## Task 4: Prefer hybrid key exchange

`TLS_KEY_EXCHANGE_GROUPS` controls key-establishment groups. The `hybrid` group combines ML-KEM and ECDHE into one shared secret. It changes key establishment, not the record cipher shown by `TLS_CIPHERSUITE`.

1. Enable hybrid key exchange on the database host. The scripts update the server and listener configuration and retain the backups created in Task 2.

    ```bash
    <copy>
    export TLS_CONFIGURE_HYBRID=YES
    ./tls_setup_host.sh
    </copy>
    ```

    If the client uses a separate host, run the combined client setup script there with the same `PDB_NAME`:

    ```bash
    <copy>
    export TLS_CONFIGURE_HYBRID=YES
    ./tls_setup_client.sh
    </copy>
    ```

    `hybrid` is listed first so endpoints that support hybrid PQC prefer it. `ec` provides a classical ECDHE fallback for a TLS 1.3 client that cannot negotiate hybrid. ML-KEM and hybrid key exchange apply only to TLS 1.3.

2. Confirm the effective configuration entries.

    ```bash
    <copy>
    grep -Ei '^[[:space:]]*(TLS_VERSION|TLS_KEY_EXCHANGE_GROUPS)[[:space:]]*=' \
      "${TNS_ADMIN:-$ORACLE_HOME/network/admin}/sqlnet.ora" \
      "${TNS_ADMIN:-$ORACLE_HOME/network/admin}/listener.ora"
    </copy>
    ```

    The SQL context does not expose the negotiated group; the `TLS_CIPHERSUITE` value is not proof of hybrid key exchange.

## Task 5: Test TLS 1.3 and TLS 1.2

Use the provided script to create connection-specific aliases and prove that the endpoint accepts both versions. Do not copy or edit TNS entries by hand.

1. Create the version-specific aliases.

    ```bash
    <copy>
    ./tls_setup_test_aliases.sh
    </copy>
    ```

    The script reads the TCPS host, port, and service from `${PDB_NAME}_tls`, then creates `${PDB_NAME}_tls13` and `${PDB_NAME}_tls12` with connection-specific TLS versions. It backs up `tnsnames.ora` before editing it. If both version aliases already exist, it leaves them unchanged; if only one exists, review the file before continuing.

2. Connect through the TLS 1.3 alias and verify the session.

    ```bash
    <copy>
    sqlplus "system@${PDB_NAME}_tls13"
    </copy>
    ```

    ```sql
    <copy>
    SELECT SYS_CONTEXT('USERENV', 'NETWORK_PROTOCOL') AS network_protocol,
           SYS_CONTEXT('USERENV', 'TLS_VERSION') AS tls_version,
           SYS_CONTEXT('USERENV', 'TLS_CIPHERSUITE') AS tls_ciphersuite
      FROM dual;
    </copy>
    ```

    The result should show `tcps` and `TLSv1.3`. On 26ai, or on 19.32 after switching to the next-generation provider, Task 4 makes `hybrid` the preferred TLS 1.3 key-exchange group when both endpoints support it.

3. Exit SQL*Plus to return to the command line.

    ```sql
    <copy>
    exit
    </copy>
    ```

4. Connect through the TLS 1.2 alias, and run the same query.

    ```bash
    <copy>
    sqlplus "system@${PDB_NAME}_tls12"
    </copy>
    ```

    The result should show `tcps` and `TLSv1.2`. The TLS 1.2 connection demonstrates backward compatibility; it does not use ML-KEM or hybrid key exchange.

### Interpret the results

1. Compare the `${PDB_NAME}_tls13` and `${PDB_NAME}_tls12` query results.

2. Read the individual values as follows.

    - `NETWORK_PROTOCOL=tcps` confirms that the database session uses Transport Layer Security.
    - `TLS_VERSION` confirms which protocol version the endpoints negotiated.
    - `TLS_CIPHERSUITE` identifies the record-layer authentication, encryption, and integrity algorithms. It does not identify the key-exchange group.

For either supported release, `hybrid` is the configured TLS 1.3 preference when the selected provider and both endpoints support it. On 19.32, this requires the next-generation provider.
The SQL context does not expose the negotiated group; the cipher output is not proof of hybrid key exchange.


If TLS 1.3 fails, confirm the selected release and provider, then confirm hybrid support on both endpoints. On 19.32, confirm that the next-generation provider is active. Reload the listener and check that the client uses the intended `TNS_ADMIN` files. If needed, restore the Task 2 backups and reload the listener.

### Optional rollback

Use `tls_restore.sh` to restore the original Oracle Net files saved before the lab. The script backs up the current files first, requires the non-production acknowledgement and explicit rollback confirmation, restarts the listener, and re-registers database services. It does not change wallets or certificates; wallet-directory backups are retained.

    ```bash
    <copy>
    ./tls_restore.sh --yes-i-understand
    </copy>
    ```

The default `original` selector restores the `.before-tls-fastlab` backups. To restore a timestamped backup instead, set `TLS_RESTORE_BACKUP` to the timestamp suffix.

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
