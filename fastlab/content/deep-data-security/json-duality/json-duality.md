# JSON Duality with Oracle Deep Data Security

## Introduction

In this FastLab, you will expose relational employee data as JSON documents and protect those documents with Oracle Deep Data Security. Emma sees only her JSON document. Marvin sees his own document plus the documents for employees who report to him.

Estimated Time: 15 minutes

### Objectives

In this lab, you will:

- Create a small relational table
- Create a JSON relational duality view
- Create employee and manager data roles
- Use data grants to filter JSON documents by employee and manager identity

### Prerequisites

This lab assumes you have:

- Oracle AI Database 26ai
- A SQL worksheet or SQL*Plus connection as a DBA user
- Privileges to create users, roles, tables, duality views, end users, data roles, and data grants

## Task 1: Create the Lab Administrator

Create a dedicated administrator for this FastLab. If you already have a user with these privileges, you can use that account instead.

1. Run this setup as a DBA user.

    ```sql
    <copy>
    CREATE USER deepsec_admin IDENTIFIED BY Oracle123;

    GRANT CREATE SESSION TO deepsec_admin WITH ADMIN OPTION;
    GRANT CREATE USER TO deepsec_admin;
    GRANT DROP USER TO deepsec_admin;
    GRANT CREATE ANY TABLE TO deepsec_admin;
    GRANT DROP ANY TABLE TO deepsec_admin;
    GRANT INSERT ANY TABLE TO deepsec_admin;
    GRANT SELECT ANY TABLE TO deepsec_admin;
    GRANT CREATE ANY VIEW TO deepsec_admin;
    GRANT DROP ANY VIEW TO deepsec_admin;
    GRANT CREATE ROLE TO deepsec_admin;
    GRANT DROP ANY ROLE TO deepsec_admin;
    GRANT GRANT ANY ROLE TO deepsec_admin;
    GRANT SELECT_CATALOG_ROLE TO deepsec_admin;

    GRANT CREATE END USER TO deepsec_admin;
    GRANT DROP END USER TO deepsec_admin;
    GRANT CREATE DATA ROLE TO deepsec_admin;
    GRANT DROP DATA ROLE TO deepsec_admin;
    GRANT GRANT ANY DATA ROLE TO deepsec_admin;
    GRANT CREATE ANY DATA GRANT TO deepsec_admin;
    GRANT DROP ANY DATA GRANT TO deepsec_admin;
    GRANT ADMINISTER ANY DATA GRANT TO deepsec_admin;
    </copy>
    ```

2. Connect as `DEEPSEC_ADMIN`.

    ```sql
    <copy>
    CONNECT deepsec_admin/Oracle123
    </copy>
    ```

## Task 2: Create Relational Data and a JSON Duality View

The table stores employee rows like the Deep Data Security FastLab. The duality view exposes each row as one JSON document in the `DATA` column.

1. Reset the lab objects, then create the schema and table.

    ```sql
    <copy>
    DROP DATA GRANT hr.HRAPP_EMPLOYEE_ACCESS;
    DROP DATA GRANT hr.HRAPP_MANAGER_ACCESS;
    DROP VIEW hr.emp_json;
    DROP USER hr CASCADE;
    </copy>
    ```

    Ignore errors if the objects do not exist yet.

2. Create the `HR` schema and the lab table.

    ```sql
    <copy>
    CREATE USER hr NO AUTHENTICATION DEFAULT TABLESPACE users;
    ALTER USER hr QUOTA UNLIMITED ON users;

    CREATE TABLE hr.employees (
      employee_id       NUMBER PRIMARY KEY,
      first_name        VARCHAR2(50) NOT NULL,
      last_name         VARCHAR2(50) NOT NULL,
      job_code          VARCHAR2(10) NOT NULL,
      department_id     NUMBER,
      ssn               VARCHAR2(20),
      phone_number      VARCHAR2(30),
      salary            NUMBER(10,2),
      user_name         VARCHAR2(128) NOT NULL,
      manager_id        NUMBER,
      manager_user_name VARCHAR2(128)
    );

    INSERT INTO hr.employees (
      employee_id, first_name, last_name, job_code, department_id, ssn,
      phone_number, salary, user_name, manager_id, manager_user_name)
    VALUES
      (1, 'Grace', 'Young', 'VP', 10, '111-11-1111', '555-100-0001', 235000,
       'grace', NULL, NULL);

    INSERT INTO hr.employees (
      employee_id, first_name, last_name, job_code, department_id, ssn,
      phone_number, salary, user_name, manager_id, manager_user_name)
    VALUES
      (2, 'Marvin', 'Morgan', 'SWE_MGR', 10, '222-22-2222', '555-100-0002', 175000,
       'marvin', 1, 'grace');

    INSERT INTO hr.employees (
      employee_id, first_name, last_name, job_code, department_id, ssn,
      phone_number, salary, user_name, manager_id, manager_user_name)
    VALUES
      (3, 'Emma', 'Baker', 'SWE2', 10, '333-33-3333', '555-100-0003', 120000,
       'emma', 2, 'marvin');

    INSERT INTO hr.employees (
      employee_id, first_name, last_name, job_code, department_id, ssn,
      phone_number, salary, user_name, manager_id, manager_user_name)
    VALUES
      (4, 'Dana', 'Lee', 'SWE3', 10, '444-44-4444', '555-100-0004', 130000,
       'dana', 2, 'marvin');

    COMMIT;
    </copy>
    ```

3. Create the JSON relational duality view.

    ```sql
    <copy>
    CREATE OR REPLACE JSON RELATIONAL DUALITY VIEW hr.emp_json AS
    SELECT JSON {
      '_id'             : employee_id,
      'firstName'       : first_name,
      'lastName'        : last_name,
      'jobCode'         : job_code,
      'departmentId'    : department_id,
      'ssn'             : ssn,
      'phoneNumber'     : phone_number,
      'salary'          : salary,
      'userName'        : user_name,
      'managerId'       : manager_id,
      'managerUserName' : manager_user_name
    }
    FROM hr.employees;
    </copy>
    ```

4. Query the view as the administrator.

    ```sql
    <copy>
    SELECT json_serialize(data PRETTY) AS employee_document
      FROM hr.emp_json
     ORDER BY json_value(data, '$._id' RETURNING NUMBER);
    </copy>
    ```

    You should see four JSON documents. Marvin is a manager for Emma and Dana because their documents contain `"managerUserName" : "marvin"`.

## Task 3: Create End Users and Data Roles

End users are identities that do not own schema objects. A standard database role lets them connect and resolve the JSON duality view. Data roles carry the Deep Data Security grants on the base table.

1. Create Emma, Marvin, and the roles they need.

    ```sql
    <copy>
    CREATE END USER emma IDENTIFIED BY Oracle123;
    CREATE END USER marvin IDENTIFIED BY Oracle123;

    CREATE ROLE direct_logon_role;
    GRANT CREATE SESSION TO direct_logon_role;
    GRANT SELECT, UPDATE ON hr.emp_json TO direct_logon_role;

    CREATE DATA ROLE HRAPP_EMPLOYEES;
    CREATE DATA ROLE HRAPP_MANAGERS;

    GRANT DATA ROLE HRAPP_EMPLOYEES TO emma;
    GRANT DATA ROLE HRAPP_EMPLOYEES TO marvin;
    GRANT DATA ROLE HRAPP_MANAGERS TO marvin;

    GRANT direct_logon_role TO HRAPP_EMPLOYEES;
    </copy>
    ```

## Task 4: Protect the JSON Documents

Create two data grants on the base table. The JSON duality view reads from `hr.employees`, so the database enforces these grants when end users query or update JSON documents through `hr.emp_json`.

1. Create the employee data grant.

    ```sql
    <copy>
    CREATE OR REPLACE DATA GRANT hr.HRAPP_EMPLOYEE_ACCESS
      AS SELECT, UPDATE(phone_number, first_name)
      ON hr.employees
      WHERE upper(user_name) = upper(ORA_END_USER_CONTEXT.username)
      TO HRAPP_EMPLOYEES;
    </copy>
    ```

2. Create the manager data grant on the base table. Managers can read direct reports, except for SSNs, and update the same columns used in the relational FastLab.

    ```sql
    <copy>
    CREATE OR REPLACE DATA GRANT hr.HRAPP_MANAGER_ACCESS
      AS SELECT (ALL COLUMNS EXCEPT ssn), UPDATE(salary, department_id, first_name)
      ON hr.employees
      WHERE upper(manager_user_name) = upper(ORA_END_USER_CONTEXT.username)
      TO HRAPP_MANAGERS;
    </copy>
    ```

3. Exit your administrator session.

    ```sql
    <copy>
    EXIT
    </copy>
    ```

## Task 5: Query as Emma and Marvin

Both users query the same JSON duality view with no user filter. Oracle Database applies the data grants on the `hr.employees` base table during execution.

1. Connect as Emma and query the view.

    ```sql
    <copy>
    CONNECT emma/Oracle123

    SELECT json_serialize(data PRETTY) AS employee_document
      FROM hr.emp_json
     ORDER BY json_value(data, '$._id' RETURNING NUMBER);
    </copy>
    ```

    Emma sees only Emma's document:

    ```json
    {
      "_id" : 3,
      "firstName" : "Emma",
      "lastName" : "Baker",
      "jobCode" : "SWE2",
      "departmentId" : 10,
      "ssn" : "333-33-3333",
      "phoneNumber" : "555-100-0003",
      "salary" : 120000,
      "userName" : "emma",
      "managerId" : 2,
      "managerUserName" : "marvin"
    }
    ```

2. Try to force access to Marvin's document.

    ```sql
    <copy>
    SELECT json_serialize(data PRETTY) AS employee_document
      FROM hr.emp_json
     WHERE json_value(data, '$.userName') = 'marvin';
    </copy>
    ```

    The query returns no rows.

3. Count Emma's visible documents.

    ```sql
    <copy>
    SELECT count(*) AS visible_documents
      FROM hr.emp_json;
    </copy>
    ```

    Emma sees one document: her own employee record.

    ```text
    VISIBLE_DOCUMENTS
    -----------------
                    1
    ```

4. Update Emma's own JSON document, then roll back.

    ```sql
    <copy>
    UPDATE hr.emp_json
       SET data = json_transform(data, SET '$.phoneNumber' = '555-555-5555')
     WHERE json_value(data, '$.userName') = 'emma';

    ROLLBACK;
    </copy>
    ```

    Emma can update her own phone number through the JSON document because `HRAPP_EMPLOYEE_ACCESS` includes `UPDATE(phone_number)`.

5. Connect as Marvin and run the same broad query.

    ```sql
    <copy>
    CONNECT marvin/Oracle123

    SELECT json_serialize(data PRETTY) AS employee_document
      FROM hr.emp_json
     ORDER BY json_value(data, '$._id' RETURNING NUMBER);
    </copy>
    ```

    Marvin sees his own document from `HRAPP_EMPLOYEE_ACCESS`, plus Emma and Dana's documents from `HRAPP_MANAGER_ACCESS`.

    ```json
    {
      "_id" : 2,
      "firstName" : "Marvin",
      "lastName" : "Morgan",
      "jobCode" : "SWE_MGR",
      "departmentId" : 10,
      "ssn" : "222-22-2222",
      "phoneNumber" : "555-100-0002",
      "salary" : 175000,
      "userName" : "marvin",
      "managerId" : 1,
      "managerUserName" : "grace"
    }
    {
      "_id" : 3,
      "firstName" : "Emma",
      "lastName" : "Baker",
      "jobCode" : "SWE2",
      "departmentId" : 10,
      "phoneNumber" : "555-100-0003",
      "salary" : 120000,
      "userName" : "emma",
      "managerId" : 2,
      "managerUserName" : "marvin"
    }
    {
      "_id" : 4,
      "firstName" : "Dana",
      "lastName" : "Lee",
      "jobCode" : "SWE3",
      "departmentId" : 10,
      "phoneNumber" : "555-100-0004",
      "salary" : 130000,
      "userName" : "dana",
      "managerId" : 2,
      "managerUserName" : "marvin"
    }
    ```

6. Count Marvin's visible documents.

    ```sql
    <copy>
    SELECT count(*) AS visible_documents
      FROM hr.emp_json;
    </copy>
    ```

    Marvin sees three documents: his own employee record, Emma's record, and Dana's record.

    ```text
    VISIBLE_DOCUMENTS
    -----------------
                    3
    ```

7. Update Emma's JSON document as Marvin, then roll back.

    ```sql
    <copy>
    UPDATE hr.emp_json
       SET data = json_transform(data, SET '$.departmentId' = 20)
     WHERE json_value(data, '$.userName') = 'emma';

    ROLLBACK;
    </copy>
    ```

    Marvin can update Emma's department through the JSON document because Emma is his direct report and `HRAPP_MANAGER_ACCESS` includes `UPDATE(department_id)`.

8. Try to force access to Grace's document.

    ```sql
    <copy>
    SELECT json_serialize(data PRETTY) AS employee_document
      FROM hr.emp_json
     WHERE json_value(data, '$.userName') = 'grace';
    </copy>
    ```

    The query returns no rows. Grace is Marvin's manager, but she is not Marvin's direct report, so neither `HRAPP_EMPLOYEE_ACCESS` nor `HRAPP_MANAGER_ACCESS` matches her document.

9. Try to update Grace's JSON document.

    ```sql
    <copy>
    UPDATE hr.emp_json
       SET data = json_transform(data, SET '$.departmentId' = 90)
     WHERE json_value(data, '$.userName') = 'grace';
    </copy>
    ```

    The statement updates zero rows. Marvin has manager access to his direct reports, not to his manager.

## Task 6: Clean Up

Run cleanup if you want to repeat the FastLab.

1. Connect as `DEEPSEC_ADMIN` and remove the security objects.

    ```sql
    <copy>
    CONNECT deepsec_admin/Oracle123

    DROP DATA GRANT hr.HRAPP_EMPLOYEE_ACCESS;
    DROP DATA GRANT hr.HRAPP_MANAGER_ACCESS;
    DROP DATA ROLE HRAPP_MANAGERS;
    DROP DATA ROLE HRAPP_EMPLOYEES;
    DROP ROLE direct_logon_role;
    DROP END USER emma;
    DROP END USER marvin;
    </copy>
    ```

2. Connect as your DBA user and drop the lab schemas.

    ```sql
    <copy>
    DROP USER hr CASCADE;
    DROP USER deepsec_admin CASCADE;
    </copy>
    ```

## Summary

You created a JSON relational duality view and protected it with Deep Data Security data grants on the `hr.employees` base table. The employee grant matches `user_name` and allows `SELECT` plus `UPDATE(phone_number, first_name)`. The manager grant matches `manager_user_name` and allows `SELECT (ALL COLUMNS EXCEPT ssn)` plus `UPDATE(salary, department_id, first_name)`.

## Acknowledgements

- **Author** - Richard C. Evans, Oracle Database Security Product Management
- **Last Updated By/Date** - Richard C. Evans, Oracle Database Security Product Management, May 2026
