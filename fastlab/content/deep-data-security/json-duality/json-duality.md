# JSON Duality with Oracle Deep Data Security

## Introduction

In this FastLab, you will expose relational employee data as JSON documents and protect those documents with Oracle Deep Data Security. Emma and Marvin run the same query, but each user sees only their own JSON document.

Estimated Time: 15 minutes

### Objectives

In this lab, you will:

- Create a small relational table
- Create a JSON relational duality view
- Create two database end users
- Use a data grant to filter JSON documents by end-user identity

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
      employee_id   NUMBER PRIMARY KEY,
      user_name     VARCHAR2(128) NOT NULL,
      display_name  VARCHAR2(100) NOT NULL,
      job_title     VARCHAR2(100) NOT NULL,
      department    VARCHAR2(60) NOT NULL,
      salary        NUMBER(10,2) NOT NULL
    );

    INSERT INTO jsonlab.employee_cards VALUES
      (1, 'emma', 'Emma Baker', 'Product Manager', 'Product', 120000);

    INSERT INTO jsonlab.employee_cards VALUES
      (2, 'marvin', 'Marvin Morgan', 'Engineering Manager', 'Engineering', 175000);

    INSERT INTO jsonlab.employee_cards VALUES
      (3, 'dana', 'Dana Lee', 'Security Analyst', 'Security', 130000);

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
      'salary'     : salary
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

    You should see three JSON documents.

## Task 3: Create End Users and a Data Role

End users are identities that do not own schema objects. A data role is the policy holder that you grant to those end users.

1. Create Emma, Marvin, and the roles they need.

    ```sql
    <copy>
    CREATE END USER emma IDENTIFIED BY Oracle123;
    CREATE END USER marvin IDENTIFIED BY Oracle123;

    CREATE ROLE direct_logon_role;
    GRANT CREATE SESSION TO direct_logon_role;

    CREATE DATA ROLE json_app_users;
    GRANT direct_logon_role TO json_app_users;

    GRANT DATA ROLE json_app_users TO emma;
    GRANT DATA ROLE json_app_users TO marvin;
    </copy>
    ```

## Task 4: Protect the JSON Documents

Create one data grant on the duality view. The predicate extracts `userName` from each JSON document and compares it to the connected end user.

1. Create the data grant.

    ```sql
    <copy>
    CREATE OR REPLACE DATA GRANT jsonlab.employee_card_json_access
      AS SELECT
      ON jsonlab.employee_card_dv
      WHERE upper(json_value(data, '$.userName' RETURNING VARCHAR2(128))) =
            upper(ORA_END_USER_CONTEXT.username)
      TO json_app_users;
    </copy>
    ```

2. Exit your administrator session.

    ```sql
    <copy>
    EXIT
    </copy>
    ```

## Task 5: Query as Emma and Marvin

Both users query the same JSON duality view with no user filter. Oracle Database adds the data grant predicate during execution.

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
      "_id" : 1,
      "userName" : "emma",
      "name" : "Emma Baker",
      "title" : "Product Manager",
      "department" : "Product",
      "salary" : 120000
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

3. Connect as Marvin and run the same broad query.

    ```sql
    <copy>
    CONNECT marvin/Oracle123

    SELECT json_serialize(data PRETTY) AS employee_document
      FROM jsonlab.employee_card_dv
     ORDER BY json_value(data, '$._id' RETURNING NUMBER);
    </copy>
    ```

    Marvin sees only Marvin's document:

    ```json
    {
      "_id" : 2,
      "userName" : "marvin",
      "name" : "Marvin Morgan",
      "title" : "Engineering Manager",
      "department" : "Engineering",
      "salary" : 175000
    }
    ```

## Task 6: Clean Up

Run cleanup if you want to repeat the FastLab.

1. Connect as `DEEPSEC_ADMIN` and remove the security objects.

    ```sql
    <copy>
    CONNECT deepsec_admin/Oracle123

    DROP DATA GRANT jsonlab.employee_card_json_access;
    DROP DATA ROLE json_app_users;
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

You created a JSON relational duality view and protected it with one Deep Data Security data grant. The application can query JSON documents, while the database enforces each end user's access boundary.

## Acknowledgements

- **Author** - Richard C. Evans, Oracle Database Security Product Management
- **Last Updated By/Date** - Richard C. Evans, Oracle Database Security Product Management, May 2026
