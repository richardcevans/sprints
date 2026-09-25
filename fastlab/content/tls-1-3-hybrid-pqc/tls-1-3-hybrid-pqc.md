# How Do You Configure TLS 1.2 and TLS 1.3 with Hybrid Post-Quantum Key Exchange?

## Introduction

Configure TLS 1.2 and TLS 1.3 on Oracle AI Database 26ai. Prefer hybrid key exchange for TLS 1.3. Verify both versions over TCPS and separate key establishment from the record cipher.

Estimated Time: 15 minutes

### Objectives

In this lab, you will:

- Configure `TLS_VERSION` to permit both TLS 1.2 and TLS 1.3.
- Configure `TLS_KEY_EXCHANGE_GROUPS` with hybrid key exchange preferred.
- Test TLS 1.3 and TLS 1.2 connections through the same TCPS endpoint.
- Verify the network protocol, negotiated TLS version, and cipher suite with `SYS_CONTEXT`.

### Prerequisites

This lab assumes you have:

- An Oracle AI Database 26ai server and a DB26ai client with TLS 1.3 support.
- An existing one-way TLS configuration with a working TCPS listener, server certificate, and trusted client certificate chain.
- OS access to the database host and client configuration files as the appropriate Oracle software owner.
- A working TCPS alias such as `pdb1_tls`, plus database credentials for the lab PDB.

**Running this lab on Oracle Database 19.32 instead of 26ai:** TLS 1.3, ML-KEM, and hybrid key exchange require the next-generation cryptographic provider. The legacy provider remains the default on 19.32 and supports TLS only through 1.2, so it cannot use TLS 1.3 settings or `TLS_KEY_EXCHANGE_GROUPS` values that depend on TLS 1.3. Before Task 3, switch providers and restart:

    ```bash
    <copy>
    python $ORACLE_HOME/bin/set_crypto_provider.py next-generation
    </copy>
    ```

    Restart the database instance and reload the listener after the switch. Confirm the provider is active before proceeding to Task 3:

    ```bash
    <copy>
    python $ORACLE_HOME/bin/set_crypto_provider.py status
    </copy>
    ```

This FastLab changes protocol and key-exchange settings. It does not create wallets, certificates, or a TCPS listener.
If TCPS is not configured, complete the [Oracle one-way TLS workshop](https://livelabs.oracle.com/ords/r/dbpm/livelabs/view-workshop?wid=3631).

## Task 1: Download and prepare the TLS scripts

Open a Terminal session on your **DBSec-Lab** VM as OS user `oracle`. The archive contains only the `tls/` directory and its scripts.

1. Create the `livelabs` directory and move into it.

    ```bash
    <copy>
    mkdir -p livelabs
    cd livelabs
    </copy>
    ```

    If you are using a remote desktop session, double-click the **Terminal** icon on the desktop.

2. Download the bundled TLS scripts.

    ```bash
    <copy>
    wget -O tls.zip https://objectstorage.us-ashburn-1.oraclecloud.com/p/BHNwcP7_8g6cj9ap6j8r3rjBky44eNnrTsm8SGQ4jijQWWzjb4pMAnuiXxS1KQ8q/n/oradbclouducm/b/dbsec_public/o/tls.zip
    </copy>
    ```

3. Extract the archive and remove the downloaded ZIP.

    ```bash
    <copy>
    unzip tls.zip
    rm -f tls.zip
    </copy>
    ```

4. Enter the extracted `tls` directory and prepare the scripts.

    ```bash
    <copy>
    cd tls
    chmod +x -- *.sh
    if command -v dos2unix >/dev/null 2>&1; then dos2unix -- *; else echo "dos2unix is not installed; the bundled scripts already use Unix line endings."; fi
    </copy>
    ```

## Task 2: Inspect the existing TLS connection

Start from a known-good TCPS connection. The `SYS_CONTEXT` values show the connection protocol, negotiated TLS version, and record-layer cipher suite.

1. Open a terminal on the database client and confirm the Oracle Net locations.

    ```bash
    <copy>
    echo "$ORACLE_HOME"
    echo "$TNS_ADMIN"
    lsnrctl status
    </copy>
    ```

2. Connect with the existing TCPS alias. Replace `db_user` with a database user from your lab environment and enter its password when prompted.

    ```bash
    <copy>
    sqlplus db_user@pdb1_tls
    </copy>
    ```

3. Verify that the connection uses TCPS and record the current TLS values.

    ```sql
    <copy>
    SELECT SYS_CONTEXT('USERENV', 'NETWORK_PROTOCOL') AS network_protocol,
           SYS_CONTEXT('USERENV', 'TLS_VERSION') AS tls_version,
           SYS_CONTEXT('USERENV', 'TLS_CIPHERSUITE') AS tls_ciphersuite
      FROM dual;
    </copy>
    ```

    The `NETWORK_PROTOCOL` value should be `tcps`. Keep this session open while you update the configuration, or exit and reconnect after the listener reload.

## Task 3: Permit TLS 1.2 and TLS 1.3

Oracle AI Database 26ai supports TLS 1.2 and TLS 1.3. Set the same compatible protocol list on the database server, listener, and client components used by this lab.

1. Back up the server network files before editing them.

    ```bash
    <copy>
    export NET_ADMIN="${ORACLE_HOME}/network/admin"
    cp -p "$NET_ADMIN/sqlnet.ora" "$NET_ADMIN/sqlnet.ora.before-tls-hybrid-fastlab"
    cp -p "$NET_ADMIN/listener.ora" "$NET_ADMIN/listener.ora.before-tls-hybrid-fastlab"
    </copy>
    ```

2. Edit the server `sqlnet.ora` and add the following parameter. If a `TLS_VERSION` entry already exists, replace its value rather than creating a second entry.

    ```text
    <copy>
    TLS_VERSION=(TLSv1.2,TLSv1.3)
    </copy>
    ```

3. Add the same `TLS_VERSION` entry to the listener `listener.ora` and to the client `sqlnet.ora` used by `pdb1_tls`. On a single-host lab, these files may be under the same network administration directory. On a separate client, edit the client file selected by `TNS_ADMIN`.

4. Reload the listener after saving `listener.ora`.

    ```bash
    <copy>
    lsnrctl reload
    </copy>
    ```

    The client and server must have at least one TLS version in common. Listing both versions preserves TLS 1.2 compatibility while allowing a TLS 1.3-capable client to negotiate TLS 1.3.

## Task 4: Prefer hybrid key exchange

`TLS_KEY_EXCHANGE_GROUPS` controls key-establishment groups. The `hybrid` group combines ML-KEM and ECDHE into one shared secret. It changes key establishment, not the record cipher shown by `TLS_CIPHERSUITE`.

1. Add it to the server and listener files, then to the client `sqlnet.ora`.

    ```text
    <copy>
    TLS_KEY_EXCHANGE_GROUPS=hybrid,ec
    </copy>
    ```

    `hybrid` is listed first so DB26ai endpoints that support hybrid PQC prefer it. `ec` provides a classical ECDHE fallback for a TLS 1.3 client that cannot negotiate hybrid. ML-KEM and hybrid key exchange apply only to TLS 1.3.

2. Reload the listener and confirm the effective configuration entries.

    ```bash
    <copy>
    lsnrctl reload
    grep -Ei '^[[:space:]]*(TLS_VERSION|TLS_KEY_EXCHANGE_GROUPS)[[:space:]]*=' \
      "$NET_ADMIN/sqlnet.ora" "$NET_ADMIN/listener.ora"
    </copy>
    ```

    If the client uses a separate `TNS_ADMIN` directory, run the same `grep` check against that client `sqlnet.ora`.

## Task 5: Test TLS 1.3 and TLS 1.2

Use connection-specific `TLS_VERSION` settings to prove that the endpoint accepts both versions.

Copy the existing `pdb1_tls` entry twice. Keep its host, port, service, wallet, and other settings unchanged.

1. Name the copied entries `pdb1_tls13` and `pdb1_tls12`. Add the following `SECURITY` section to each entry:

    ```text
    <copy>
    (SECURITY=(TLS_VERSION=TLSv1.3))
    </copy>
    ```

    Use `TLSv1.2` in the `pdb1_tls12` entry. In `tnsnames.ora`, do not wrap this value in parentheses; that form is for `sqlnet.ora` and `listener.ora`.

2. Connect through the TLS 1.3 alias and verify the session.

    ```bash
    <copy>
    sqlplus db_user@pdb1_tls13
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

    The result should show `tcps` and `TLSv1.3`. Both DB26ai endpoints support hybrid, so Task 4 makes it the preferred TLS 1.3 key exchange.

3. Exit SQL*Plus, connect through the TLS 1.2 alias, and run the same query.

    ```bash
    <copy>
    sqlplus db_user@pdb1_tls12
    </copy>
    ```

    The result should show `tcps` and `TLSv1.2`. The TLS 1.2 connection demonstrates backward compatibility; it does not use ML-KEM or hybrid key exchange.

### Interpret the results

1. Compare the `pdb1_tls13` and `pdb1_tls12` query results.

2. Read the individual values as follows.

    - `NETWORK_PROTOCOL=tcps` confirms that the database session uses Transport Layer Security.
    - `TLS_VERSION` confirms which protocol version the endpoints negotiated.
    - `TLS_CIPHERSUITE` identifies the record-layer authentication, encryption, and integrity algorithms. It does not identify the key-exchange group.

For this lab, hybrid is the expected TLS 1.3 result. Both endpoints support DB26ai hybrid PQC, and `hybrid` is listed first.
The SQL context does not expose the negotiated group; the cipher output is not proof of hybrid key exchange.


If TLS 1.3 fails, confirm hybrid support on both DB26ai endpoints. Reload the listener and check that the client uses the intended `TNS_ADMIN` files. If needed, restore the Task 3 backups and reload the listener.

You may now proceed to the next lab.


## Signature Workshop

Ready to dive deeper? These workshops move from TLS setup to a complete encrypted database connection.

👉 [Successfully protect your database communication using 1-way Transport Layer Security (TLS)](https://livelabs.oracle.com/ords/r/dbpm/livelabs/view-workshop?wid=3631)

## Learn More

- [Oracle AI Database 26ai Security Guide: Transport Layer Security](https://docs.oracle.com/en/database/oracle/oracle-database/26/dbseg/configuring-transport-layer-security-encryption.html)
- [Oracle AI Database 26ai Net Services Reference: `sqlnet.ora` Parameters](https://docs.oracle.com/en/database/oracle/oracle-database/26/netrf/parameters-for-the-sqlnet.ora.html)
- [Oracle Database 19c Now Supports TLS 1.3, Post-Quantum Cryptography, and FIPS 140-3 Mode](https://blogs.oracle.com/database/database-19c-now-supports-tls-1-3-post-quantum-cryptography)
- [Both is better - Oracle AI Database 26ai adds hybrid-mode quantum-resistant support](https://blogs.oracle.com/database/hybrid-pqc)
- [Announcing support for TLS 1.3 in Oracle Database 23ai](https://blogs.oracle.com/database/announcing-tls13)
- [Oracle AI Database walletless TLS](https://www.braddiggs.com/2026/08/oracle-ai-database-walletless-tls.html) (community article)

## Acknowledgements

- **Author** - Richard C. Evans
- **Last Updated By/Date** - Richard C. Evans, September 2026
- **Technical references** - Oracle Database Security documentation and Oracle Database Insider articles listed above
