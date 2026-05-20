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

The table stores employee cards as rows. The duality view exposes each row as one JSON document in the `DATA` column.

1. Create the schema and table.

    ```sql
    <copy>
    CREATE USER jsonlab NO AUTHENTICATION DEFAULT TABLESPACE users;
    ALTER USER jsonlab QUOTA UNLIMITED ON users;

    CREATE TABLE jsonlab.employee_cards (
      employee_id       NUMBER PRIMARY KEY,
      user_name         VARCHAR2(128) NOT NULL,
      display_name      VARCHAR2(100) NOT NULL,
      job_title         VARCHAR2(100) NOT NULL,
      department        VARCHAR2(60) NOT NULL,
      salary            NUMBER(10,2) NOT NULL,
      manager_user_name VARCHAR2(128)
    );

    INSERT INTO jsonlab.employee_cards VALUES
      (1, 'grace', 'Grace Young', 'VP Engineering', 'Engineering', 235000, NULL);

    INSERT INTO jsonlab.employee_cards VALUES
      (2, 'marvin', 'Marvin Morgan', 'Engineering Manager', 'Engineering', 175000, 'grace');

    INSERT INTO jsonlab.employee_cards VALUES
      (3, 'emma', 'Emma Baker', 'Product Manager', 'Product', 120000, 'marvin');

    INSERT INTO jsonlab.employee_cards VALUES
      (4, 'dana', 'Dana Lee', 'Security Analyst', 'Security', 130000, 'marvin');

    COMMIT;
    </copy>
    ```

2. Create the JSON relational duality view.

    ```sql
    <copy>
    CREATE OR REPLACE JSON RELATIONAL DUALITY VIEW jsonlab.employee_card_dv AS
    SELECT JSON {
      '_id'        : employee_id,
      'userName'   : user_name,
      'name'       : display_name,
      'title'      : job_title,
      'department' : department,
      'salary'     : salary,
      'managerUserName' : manager_user_name
    }
    FROM jsonlab.employee_cards;
    </copy>
    ```

3. Query the view as the administrator.

    ```sql
    <copy>
    SELECT json_serialize(data PRETTY) AS employee_document
      FROM jsonlab.employee_card_dv
     ORDER BY json_value(data, '$._id' RETURNING NUMBER);
    </copy>
    ```

    You should see four JSON documents. Marvin is a manager for Emma and Dana because their documents contain `"managerUserName" : "marvin"`.

## Task 3: Create End Users and Data Roles

End users are identities that do not own schema objects. A data role is the policy holder that you grant to those end users.

1. Create Emma, Marvin, and the roles they need.

    ```sql
    <copy>
    CREATE END USER emma IDENTIFIED BY Oracle123;
    CREATE END USER marvin IDENTIFIED BY Oracle123;

    CREATE ROLE direct_logon_role;
    GRANT CREATE SESSION TO direct_logon_role;

    CREATE DATA ROLE HRAPP_EMPLOYEES;
    CREATE DATA ROLE HRAPP_MANAGERS;

    GRANT DATA ROLE HRAPP_EMPLOYEES TO emma;
    GRANT DATA ROLE HRAPP_EMPLOYEES TO marvin;
    GRANT DATA ROLE HRAPP_MANAGERS TO marvin;

    GRANT direct_logon_role TO HRAPP_EMPLOYEES;
    </copy>
    ```

## Task 4: Protect the JSON Documents

Create two data grants on the duality view. The employee grant allows `SELECT` and `UPDATE(data)` for the employee's own JSON document. The manager grant allows `SELECT` and `UPDATE(data)` for JSON documents where the connected user is the manager.

1. Create the employee data grant.

    ```sql
    <copy>
    CREATE OR REPLACE DATA GRANT jsonlab.HRAPP_EMPLOYEE_ACCESS
      AS SELECT, UPDATE(data)
      ON jsonlab.employee_card_dv
      WHERE upper(json_value(data, '$.userName' RETURNING VARCHAR2(128))) =
            upper(ORA_END_USER_CONTEXT.username)
      TO HRAPP_EMPLOYEES;
    </copy>
    ```

2. Create the JSON version of the manager data grant. This is the same idea as `HRAPP_MANAGER_ACCESS` in the relational FastLab, but the predicate reads the manager identity from the JSON document.

    ```sql
    <copy>
    CREATE OR REPLACE DATA GRANT jsonlab.HRAPP_MANAGER_ACCESS
      AS SELECT, UPDATE(data)
      ON jsonlab.employee_card_dv
      WHERE upper(json_value(data, '$.managerUserName' RETURNING VARCHAR2(128))) =
            upper(ORA_END_USER_CONTEXT.username)
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

Both users query the same JSON duality view with no user filter. Oracle Database adds the employee and manager data grant predicates during execution.

1. Connect as Emma and query the view.

    ```sql
    <copy>
    CONNECT emma/Oracle123

    SELECT json_serialize(data PRETTY) AS employee_document
      FROM jsonlab.employee_card_dv
     ORDER BY json_value(data, '$._id' RETURNING NUMBER);
    </copy>
    ```

    Emma sees only Emma's document:

    ```json
    {
      "_id" : 3,
      "userName" : "emma",
      "name" : "Emma Baker",
      "title" : "Product Manager",
      "department" : "Product",
      "salary" : 120000,
      "managerUserName" : "marvin"
    }
    ```

2. Try to force access to Marvin's document.

    ```sql
    <copy>
    SELECT json_serialize(data PRETTY) AS employee_document
      FROM jsonlab.employee_card_dv
     WHERE json_value(data, '$.userName') = 'marvin';
    </copy>
    ```

    The query returns no rows.

3. Count Emma's visible documents.

    ```sql
    <copy>
    SELECT count(*) AS visible_documents
      FROM jsonlab.employee_card_dv;
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
    UPDATE jsonlab.employee_card_dv
       SET data = json_transform(data, SET '$.department' = 'Product Strategy')
     WHERE json_value(data, '$.userName') = 'emma';

    ROLLBACK;
    </copy>
    ```

    Emma can update her own document because `HRAPP_EMPLOYEE_ACCESS` includes `UPDATE(data)`.

5. Connect as Marvin and run the same broad query.

    ```sql
    <copy>
    CONNECT marvin/Oracle123

    SELECT json_serialize(data PRETTY) AS employee_document
      FROM jsonlab.employee_card_dv
     ORDER BY json_value(data, '$._id' RETURNING NUMBER);
    </copy>
    ```

    Marvin sees his own document from `HRAPP_EMPLOYEE_ACCESS`, plus Emma and Dana's documents from `HRAPP_MANAGER_ACCESS`.

    ```json
    {
      "_id" : 2,
      "userName" : "marvin",
      "name" : "Marvin Morgan",
      "title" : "Engineering Manager",
      "department" : "Engineering",
      "salary" : 175000,
      "managerUserName" : "grace"
    }
    {
      "_id" : 3,
      "userName" : "emma",
      "name" : "Emma Baker",
      "title" : "Product Manager",
      "department" : "Product",
      "salary" : 120000,
      "managerUserName" : "marvin"
    }
    {
      "_id" : 4,
      "userName" : "dana",
      "name" : "Dana Lee",
      "title" : "Security Analyst",
      "department" : "Security",
      "salary" : 130000,
      "managerUserName" : "marvin"
    }
    ```

6. Count Marvin's visible documents.

    ```sql
    <copy>
    SELECT count(*) AS visible_documents
      FROM jsonlab.employee_card_dv;
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
    UPDATE jsonlab.employee_card_dv
       SET data = json_transform(data, SET '$.department' = 'Product Strategy')
     WHERE json_value(data, '$.userName') = 'emma';

    ROLLBACK;
    </copy>
    ```

    Marvin can update Emma's document because Emma is his direct report and `HRAPP_MANAGER_ACCESS` includes `UPDATE(data)`.

8. Try to force access to Grace's document.

    ```sql
    <copy>
    SELECT json_serialize(data PRETTY) AS employee_document
      FROM jsonlab.employee_card_dv
     WHERE json_value(data, '$.userName') = 'grace';
    </copy>
    ```

    The query returns no rows. Grace is Marvin's manager, but she is not Marvin's direct report, so neither `HRAPP_EMPLOYEE_ACCESS` nor `HRAPP_MANAGER_ACCESS` matches her document.

9. Try to update Grace's JSON document.

    ```sql
    <copy>
    UPDATE jsonlab.employee_card_dv
       SET data = json_transform(data, SET '$.department' = 'Executive')
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

    DROP DATA GRANT jsonlab.HRAPP_EMPLOYEE_ACCESS;
    DROP DATA GRANT jsonlab.HRAPP_MANAGER_ACCESS;
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
    DROP USER jsonlab CASCADE;
    DROP USER deepsec_admin CASCADE;
    </copy>
    ```

## Summary

You created a JSON relational duality view and protected it with Deep Data Security data grants. The employee grant matches the document's `userName`; the manager grant matches `managerUserName`. Both grants include explicit `SELECT` and `UPDATE(data)` clauses, while the database still enforces each end user's access boundary.

## Acknowledgements

- **Author** - Richard C. Evans, Oracle Database Security Product Management
- **Last Updated By/Date** - Richard C. Evans, Oracle Database Security Product Management, May 2026
