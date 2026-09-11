# Enforce Mandatory Access Control with Oracle Deep Data Security

## Introduction

This **Oracle Deep Data Security LiveLabs FastLab** shows how Mandatory Access Control (MAC) keeps row-level authorization consistent across every access path to sensitive database objects.

Applications often expose data through views, reporting tools, APIs, copilots, and direct SQL access. If a user can reach the same data through more than one path, each path must enforce the same authorization rule. This matters for sensitive data such as Personally Identifiable Information (PII), Protected Health Information (PHI), salary data, or employee records.

In this lab, Emma is allowed to see only her own employee record. You will first create a view that exposes all employee rows. Then you will see how the table and view can return different results. Finally, you will enable the Deep Data Security `USE DATA GRANTS ONLY` setting on the base table and verify that Emma sees only her own row whether she queries the table directly or through the view.

Estimated Time: 15 minutes

### Objectives

In this lab, you will:

- Create a small HR employee table with sensitive data.
- Create an Oracle Database end user and a data role.
- Grant restricted access to the base table with a data grant.
- Grant broad access to a view and observe the inconsistent result.
- Identify the risky combination before users discover it through query results.
- Enable `USE DATA GRANTS ONLY` on the base table to enforce MAC.
- Verify that table and view access return the same authorized data.

### Prerequisites

This lab is a walk-through of the technology. To run the SQL, you need:

- An **Oracle AI Database 26ai** instance.
- A DBA account or a dedicated Deep Data Security administrator.
- SQL\*Plus, SQLcl, or another SQL worksheet connected to the database.

## Task 1: Create the HR Schema and Sample Data

The first task creates an `hr.employees` table with five employees. The `user_name` column will be used in a data grant predicate to match the authenticated end user to their own row.

> **Connection:** Run as a DBA user or your Deep Data Security administrator.

1. Create a schema-only HR account.

    ```sql
    <copy>
    CREATE USER hr NO AUTHENTICATION DEFAULT TABLESPACE users;
    ALTER USER hr QUOTA UNLIMITED ON users;
    </copy>
    ```

2. Create the employee table and load sample data.

    ```sql
    <copy>
    CREATE TABLE hr.employees (
      employee_id   NUMBER PRIMARY KEY,
      first_name    VARCHAR2(50),
      last_name     VARCHAR2(50),
      user_name     VARCHAR2(128),
      department_id NUMBER,
      salary        NUMBER(10,2),
      ssn           VARCHAR2(20));

    INSERT INTO hr.employees VALUES (1, 'Victoria', 'Young', 'victoria', 10, 235000, '111-11-1111');
    INSERT INTO hr.employees VALUES (2, 'Marvin',   'Morgan', 'marvin',   20, 175000, '222-22-2222');
    INSERT INTO hr.employees VALUES (3, 'Chris',    'Davis',  'chris',    20, 145000, '333-33-3333');
    INSERT INTO hr.employees VALUES (4, 'Emma',     'Baker',  'emma',     20, 120000, '444-44-4444');
    INSERT INTO hr.employees VALUES (5, 'Taylor',   'Lee',    'taylor',   30, 130000, '555-55-5555');

    COMMIT;
    </copy>
    ```

3. Create a view that exposes all employee rows.

    ```sql
    <copy>
    CREATE OR REPLACE VIEW hr.employees_view AS
      SELECT * FROM hr.employees;
    </copy>
    ```

4. Verify the base table contains five rows.

    ```sql
    <copy>
    SELECT employee_id, first_name, user_name, salary
      FROM hr.employees
     ORDER BY employee_id;
    </copy>
    ```

    | EMPLOYEE\_ID | FIRST\_NAME | USER\_NAME | SALARY |
    |---|---|---|---|
    | 1 | Victoria | victoria | 235000 |
    | 2 | Marvin | marvin | 175000 |
    | 3 | Chris | chris | 145000 |
    | 4 | Emma | emma | 120000 |
    | 5 | Taylor | taylor | 130000 |
    {: title="Sample employee data"}

## Task 2: Create Emma and the Employee Data Role

Emma will connect as an Oracle Database end user. The `employee_role` data role will hold the data grants used in this lab.

> **Connection:** Run as a DBA user or your Deep Data Security administrator.

1. Create Emma as an end user.

    ```sql
    <copy>
    CREATE END USER emma IDENTIFIED BY Oracle123;
    </copy>
    ```

2. Create a database role for direct SQL connections and a data role for employee access.

    ```sql
    <copy>
    CREATE ROLE direct_logon_role;
    GRANT CREATE SESSION TO direct_logon_role;

    CREATE DATA ROLE employee_role;
    GRANT direct_logon_role TO employee_role;
    GRANT DATA ROLE employee_role TO emma;
    </copy>
    ```

3. Verify the data role assignment.

    ```sql
    <copy>
    SELECT data_role, role_type, grantee, grantee_type
      FROM dba_data_role_grants
     WHERE grantee = 'EMMA'
        OR data_role = 'EMPLOYEE_ROLE'
     ORDER BY data_role, grantee;
    </copy>
    ```

    Emma now has a data role that can hold data grants and a database role that allows her to connect.

## Task 3: Create Conflicting Access Paths

This task creates the security gap. Emma receives restricted access to the base table, but broad access to the view.

> **Connection:** Run as a DBA user or your Deep Data Security administrator.

1. Grant Emma own-record-only access to the base table through `employee_role`.

    ```sql
    <copy>
    CREATE OR REPLACE DATA GRANT hr.employees_own_record
      AS SELECT ON hr.employees
      WHERE upper(user_name) = upper(ORA_END_USER_CONTEXT.username)
      TO employee_role;
    </copy>
    ```

2. Grant broad access to the view through the same data role.

    ```sql
    <copy>
    CREATE OR REPLACE DATA GRANT hr.employees_view_grant
      AS SELECT ON hr.employees_view
      TO employee_role;
    </copy>
    ```

3. Review the data grants.

    ```sql
    <copy>
    SELECT object_name, grant_name, grantee, predicate
      FROM dba_data_grants
     WHERE object_owner = 'HR'
       AND object_name IN ('EMPLOYEES', 'EMPLOYEES_VIEW')
     ORDER BY object_name, grant_name;
    </copy>
    ```

    | OBJECT\_NAME | GRANT\_NAME | GRANTEE | PREDICATE |
    |---|---|---|---|
    | EMPLOYEES | EMPLOYEES\_OWN\_RECORD | EMPLOYEE\_ROLE | `upper(user_name) = upper(ORA_END_USER_CONTEXT.username)` |
    | EMPLOYEES\_VIEW | EMPLOYEES\_VIEW\_GRANT | EMPLOYEE\_ROLE | |
    {: title="Data grants on the table and view"}

    The table grant has a row predicate. The view grant does not. That difference is the risk you will inspect and test next.

## Task 4: Identify the Risk Before Exposure

Before a user discovers inconsistent results, administrators can look for the conditions that make the exposure possible: protected tables without MAC enabled, views that depend on those tables, and different grants across those access paths.

> **Connection:** Run as a DBA user or your Deep Data Security administrator.

1. Find protected tables that do not have MAC enabled.

    ```sql
    <copy>
    SELECT DISTINCT
           object_owner,
           object_name,
           object_type,
           use_data_grants_only
      FROM dba_data_grants
     WHERE object_type = 'TABLE'
       AND use_data_grants_only = FALSE
     ORDER BY object_owner, object_name;
    </copy>
    ```

    In this lab, `HR.EMPLOYEES` appears because the table has a data grant and MAC is not enabled yet.

2. Find views that depend on the protected table.

    ```sql
    <copy>
    SELECT owner AS view_owner,
           name  AS view_name
      FROM dba_dependencies
     WHERE type = 'VIEW'
       AND referenced_owner = 'HR'
       AND referenced_name = 'EMPLOYEES'
     ORDER BY owner, name;
    </copy>
    ```

    ```text
    VIEW_OWNER  VIEW_NAME
    ----------  --------------
    HR          EMPLOYEES_VIEW
    ```

3. Compare the grants on the base table and the view.

    ```sql
    <copy>
    SELECT object_name, grant_name, grantee, predicate
      FROM dba_data_grants
     WHERE object_owner = 'HR'
       AND object_name IN ('EMPLOYEES', 'EMPLOYEES_VIEW')
     ORDER BY object_name, grant_name;
    </copy>
    ```

    The red flag is simple: the base table has a predicate, but the view does not. That means a role can have restricted access through one path and broader access through another.

## Task 5: Observe the Inconsistent Access

When Emma queries the base table, the table data grant restricts the result to her own row. When Emma queries the view, the view owner can access the base table and the broad view grant exposes all rows.

1. Connect as Emma.

    ```text
    <copy>
    sqlplus emma/Oracle123@hrdb
    </copy>
    ```

2. Confirm the end-user identity used by the data grant predicate.

    ```sql
    <copy>
    SELECT ORA_END_USER_CONTEXT.username FROM dual;
    </copy>
    ```

    ```text
    USERNAME
    --------------------------------------------------------------------------------
    "EMMA"
    ```

3. Query the base table.

    ```sql
    <copy>
    SELECT first_name
      FROM hr.employees
     ORDER BY first_name;
    </copy>
    ```

    ```text
    FIRST_NAME
    ----------
    Emma

    1 row selected.
    ```

4. Query the view.

    ```sql
    <copy>
    SELECT first_name
      FROM hr.employees_view
     ORDER BY first_name;
    </copy>
    ```

    ```text
    FIRST_NAME
    ----------
    Chris
    Emma
    Marvin
    Taylor
    Victoria

    5 rows selected.
    ```

    Emma should not see every employee record. The view has become an alternate access path that returns more data than the base table.

## Task 6: Enable Mandatory Access Control

Deep Data Security provides the `USE DATA GRANTS ONLY` setting to enforce a Mandatory Access Control model on a table.

When `USE DATA GRANTS ONLY` is enabled:

- End users cannot access the table unless they hold the required data grant.
- Object privileges and system privileges do not bypass the data grant requirement for end-user access.
- Data grants on the base table are enforced consistently, including when the table is accessed through a view.

> **Connection:** Switch back to your DBA user or Deep Data Security administrator.

1. Enable MAC on the `hr.employees` table.

    ```sql
    <copy>
    SET USE DATA GRANTS ONLY ON hr.employees ENABLED;
    </copy>
    ```

2. Confirm the setting is enabled.

    ```sql
    <copy>
    SELECT DISTINCT object_owner, object_name, use_data_grants_only
      FROM dba_data_grants
     WHERE object_owner = 'HR'
       AND object_name = 'EMPLOYEES';
    </copy>
    ```

    ```text
    OBJECT_OWNER  OBJECT_NAME  USE_DATA_GRANTS_ONLY
    ------------  -----------  --------------------
    HR            EMPLOYEES    TRUE
    ```

## Task 7: Verify Consistent Enforcement

Now Emma should see only her own row from both the table and the view.

1. Connect as Emma again.

    ```text
    <copy>
    sqlplus emma/Oracle123@hrdb
    </copy>
    ```

2. Query the base table.

    ```sql
    <copy>
    SELECT first_name
      FROM hr.employees
     ORDER BY first_name;
    </copy>
    ```

    ```text
    FIRST_NAME
    ----------
    Emma

    1 row selected.
    ```

3. Query the view.

    ```sql
    <copy>
    SELECT first_name
      FROM hr.employees_view
     ORDER BY first_name;
    </copy>
    ```

    ```text
    FIRST_NAME
    ----------
    Emma

    1 row selected.
    ```

    The result is now consistent. Emma cannot bypass the base-table data grant by querying the view. The database enforces the same row policy regardless of the access path.

## Task 8: Clean Up (Optional)

If you want to remove everything created in this lab, run the following steps as your DBA user or Deep Data Security administrator.

1. Disable `USE DATA GRANTS ONLY` before dropping the demo objects.

    ```sql
    <copy>
    SET USE DATA GRANTS ONLY ON hr.employees DISABLED;
    </copy>
    ```

2. Drop the data grants.

    ```sql
    <copy>
    DROP DATA GRANT hr.employees_view_grant;
    DROP DATA GRANT hr.employees_own_record;
    </copy>
    ```

3. Drop the data role, database role, end user, and HR schema.

    ```sql
    <copy>
    DROP DATA ROLE employee_role;
    DROP ROLE direct_logon_role;
    DROP END USER emma;
    DROP USER hr CASCADE;
    </copy>
    ```

## What You Built

You created a MAC demonstration for Oracle Deep Data Security:

| Component | Purpose |
|---|---|
| `hr.employees` | Base table containing sensitive employee data |
| `hr.employees_view` | Alternate access path to the same table |
| `emma` | Oracle Database end user |
| `employee_role` | Data role assigned to Emma |
| `hr.employees_own_record` | Data grant that restricts Emma to her own row |
| `hr.employees_view_grant` | Broad view grant that demonstrates the access gap before MAC |
| `USE DATA GRANTS ONLY` | MAC setting that forces consistent data grant enforcement on the base table |
{: title="Lab components"}

The key result is simple: after MAC is enabled, data grants on the base table are mandatory. Emma gets the same authorized result whether she queries the table directly or through a view.

You may now proceed to the next lab.

## Learn More

- [Oracle AI Database 26ai Documentation](https://docs.oracle.com/en/database/)
- [Oracle Deep Data Security Configuration Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/index.html)
- [FastLab: Getting Started with Oracle Deep Data Security](../end-user-data-grants/index.html)
- [FastLab: Oracle Deep Data Security with Microsoft Entra ID](../data-grants/index.html)

## Acknowledgements

- **Author** - Richard C. Evans, Oracle Database Security Product Management
- **Last Updated By/Date** - Richard C. Evans, Oracle Database Security Product Management, May 2026
