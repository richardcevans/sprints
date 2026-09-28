WHENEVER OSERROR EXIT FAILURE
WHENEVER SQLERROR EXIT FAILURE
SET VERIFY OFF
SET LINESIZE 200
COLUMN network_protocol FORMAT A18
COLUMN tls_version FORMAT A14
COLUMN tls_ciphersuite FORMAT A90
SELECT SYS_CONTEXT('USERENV', 'NETWORK_PROTOCOL') AS network_protocol,
       SYS_CONTEXT('USERENV', 'TLS_VERSION') AS tls_version,
       SYS_CONTEXT('USERENV', 'TLS_CIPHERSUITE') AS tls_ciphersuite
  FROM dual;
DECLARE
  actual_protocol    VARCHAR2(32) := NVL(LOWER(SYS_CONTEXT('USERENV', 'NETWORK_PROTOCOL')), 'missing');
  actual_tls_version VARCHAR2(32) := NVL(SYS_CONTEXT('USERENV', 'TLS_VERSION'), 'missing');
  numeric_version    VARCHAR2(32);
BEGIN
  numeric_version := NVL(REGEXP_REPLACE(actual_tls_version, '[^0-9.]', ''), 'missing');
  IF actual_protocol <> 'tcps' OR numeric_version <> '&1' THEN
    RAISE_APPLICATION_ERROR(
      -20001,
      'Expected tcps and TLS &1; got ' || actual_protocol || ' and ' || actual_tls_version
    );
  END IF;
END;
/
EXIT SUCCESS
