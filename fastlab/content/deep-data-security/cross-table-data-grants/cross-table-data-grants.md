# LiveLabs FastLab: Cross-table Data Grants with Oracle Deep Data Security

## Introduction

This FastLab extends the Oracle Deep Data Security data grants lab to show how authorization can propagate from one table to another. In a real application, the sensitive data a user can see rarely lives in one table. An employee record may have related paystubs, contact details, goals, documents, orders, attachments, or line items. You do not want to maintain separate user-specific predicates for every child table.

A **cross-table data grant** solves that problem. It grants access to rows in a child table only when the end user already has the required data privilege on the matching parent row. The grant has no `TO` clause. Access flows through the parent object's data grants at run time.

Estimated Time: 15 minutes

### Objectives

In this lab, you will:

- Create a child table related to `HR.EMPLOYEES`
- Create cross-table data grants using `WHEN ... GRANTED ON`
- Derive child-row visibility from the employee rows an end user can already see
- Use parent column privileges to distinguish own-record access from manager access
- Compare Emma's and Marvin's results from the same query

## The Challenge

The previous Deep Data Security FastLab protects `HR.EMPLOYEES`. Emma can see only her own employee row. Marvin can see his own row plus his direct reports, but he cannot see their SSNs. That works for one table.

Most applications join multiple tables. If a paystub row belongs to an employee, the paystub should be visible only when the current end user is authorized to see the matching employee row. A cross-table data grant lets Oracle Database enforce that relationship directly:

| Concept | In this lab |
|---|---|
| Parent object | `HR.EMPLOYEES` |
| Child object | `HR.EMP_PAYSTUBS` |
| Own-paystub check | `WHEN SELECT(ssn) GRANTED ON HR.EMPLOYEES` |
| Manager-paystub check | `WHEN UPDATE(department_id) GRANTED ON HR.EMPLOYEES` |
| Join predicate | `EMP_PAYSTUBS.employee_id = EMPLOYEES.employee_id` |
| Result | Paystub rows appear only when matching employee rows are already authorized |
{: title="Cross-table grant model"}

## Prerequisites

Complete [Getting Started with Oracle Deep Data Security](../end-user-data-grants/index.html) first. This lab builds on the HR schema, end users, data roles, and base data grants created in that FastLab.

This lab assumes the following objects already exist:

- `HR.EMPLOYEES`
- `HRAPP_EMPLOYEES`
- `HRAPP_MANAGERS`
- An employee data grant that lets an employee see their own `HR.EMPLOYEES` row, including `SSN`
- A manager data grant that lets a manager see direct reports in `HR.EMPLOYEES`, excluding `SSN`, and update `department_id`

> **Connection:** Run Tasks 1 through 3 as a DBA user or your Deep Data Security administrator. Run Task 4 as Emma and Marvin.

## Task 1: Create a child table

Create a paystub table that belongs to `HR` and references `HR.EMPLOYEES`. Each row belongs to one employee.

1. Create the table.

      ```sql
      <copy>
      CREATE TABLE hr.emp_paystubs (
        paystub_id        NUMBER PRIMARY KEY,
        employee_id       NUMBER,
        pay_period_start  DATE,
        pay_period_end    DATE,
        gross_pay         NUMBER(8,2),
        net_pay           NUMBER(8,2),
        tax_withheld      NUMBER(8,2),
        deductions        NUMBER(8,2),
        pay_date          DATE,
        bank_account      VARCHAR2(50),
        FOREIGN KEY (employee_id) REFERENCES hr.employees(employee_id)
      );
      </copy>
      ```

2. Insert one sample paystub for each employee in the prerequisite FastLab.

      ```sql
      <copy>
      INSERT INTO hr.emp_paystubs VALUES
        (9101, 1, DATE '2026-03-01', DATE '2026-03-15',
         9791.67, 7050.00, 1958.33, 783.34, DATE '2026-03-16', 'xxxxxxx1111');

      INSERT INTO hr.emp_paystubs VALUES
        (9201, 2, DATE '2026-03-01', DATE '2026-03-15',
         7291.67, 5250.00, 1458.33, 583.34, DATE '2026-03-16', 'xxxxxxx2222');

      INSERT INTO hr.emp_paystubs VALUES
        (9301, 3, DATE '2026-03-01', DATE '2026-03-15',
         5000.00, 3600.00, 1000.00, 400.00, DATE '2026-03-16', 'xxxxxxx3333');

      INSERT INTO hr.emp_paystubs VALUES
        (9401, 4, DATE '2026-03-01', DATE '2026-03-15',
         3958.33, 2850.00, 791.67, 316.66, DATE '2026-03-16', 'xxxxxxx4444');

      INSERT INTO hr.emp_paystubs VALUES
        (9501, 5, DATE '2026-03-01', DATE '2026-03-15',
         5416.67, 3900.00, 1083.33, 433.34, DATE '2026-03-16', 'xxxxxxx5555');

      INSERT INTO hr.emp_paystubs VALUES
        (9601, 6, DATE '2026-03-01', DATE '2026-03-15',
         6041.67, 4350.00, 1208.33, 483.34, DATE '2026-03-16', 'xxxxxxx6666');

      INSERT INTO hr.emp_paystubs VALUES
        (9701, 7, DATE '2026-03-01', DATE '2026-03-15',
         3833.33, 2775.00, 766.67, 291.66, DATE '2026-03-16', 'xxxxxxx7777');

      COMMIT;
      </copy>
      ```

3. As the DBA, verify all rows exist before data grant enforcement is applied to end users.

      ```sql
      <copy>
      SELECT paystub_id, employee_id, gross_pay, net_pay, tax_withheld,
             deductions, bank_account
        FROM hr.emp_paystubs
       ORDER BY employee_id;
      </copy>
      ```

      | PAYSTUB_ID | EMPLOYEE_ID | GROSS_PAY | NET_PAY | TAX_WITHHELD | DEDUCTIONS | BANK_ACCOUNT |
      |---|---|---|---|---|---|---|
      | 9101 | 1 | 9791.67 | 7050.00 | 1958.33 | 783.34 | xxxxxxx1111 |
      | 9201 | 2 | 7291.67 | 5250.00 | 1458.33 | 583.34 | xxxxxxx2222 |
      | 9301 | 3 | 5000.00 | 3600.00 | 1000.00 | 400.00 | xxxxxxx3333 |
      | 9401 | 4 | 3958.33 | 2850.00 | 791.67 | 316.66 | xxxxxxx4444 |
      | 9501 | 5 | 5416.67 | 3900.00 | 1083.33 | 433.34 | xxxxxxx5555 |
      | 9601 | 6 | 6041.67 | 4350.00 | 1208.33 | 483.34 | xxxxxxx6666 |
      | 9701 | 7 | 3833.33 | 2775.00 | 766.67 | 291.66 | xxxxxxx7777 |
      {: title="All paystubs before end-user enforcement"}

## Task 2: Create cross-table data grants

A regular data grant names its grantees with `TO HRAPP_EMPLOYEES`. A cross-table data grant does not. Instead, it says: if the current end user has the required privilege on a matching parent row, grant the listed privilege on the child row.

The protected object in the `ON` clause is the **child**. The object in the `GRANTED ON` clause is the **parent**.

1. Create a cross-table grant that lets employees read their own paystubs. The parent check requires `SELECT(ssn)` on `HR.EMPLOYEES`.

      ```sql
      <copy>
      CREATE OR REPLACE DATA GRANT hr.paystubs_self_access
        AS SELECT
        ON hr.emp_paystubs
        WHEN SELECT (ssn) GRANTED ON hr.employees
        WHERE hr.emp_paystubs.employee_id = hr.employees.employee_id;
      </copy>
      ```

   In the prerequisite lab, employees can read `SSN` only for their own employee row. Managers can read direct-report rows, but the manager data grant excludes `SSN`. That makes `SELECT(ssn)` a useful parent privilege for deriving full self-service paystub access.

2. Create a second cross-table grant that lets managers read direct reports' paystubs, but excludes the `bank_account` column. The parent check requires `UPDATE(department_id)` on `HR.EMPLOYEES`.

      ```sql
      <copy>
      CREATE OR REPLACE DATA GRANT hr.paystubs_manager_access
        AS SELECT (ALL COLUMNS EXCEPT bank_account)
        ON hr.emp_paystubs
        WHEN UPDATE (department_id) GRANTED ON hr.employees
        WHERE hr.emp_paystubs.employee_id = hr.employees.employee_id;
      </copy>
      ```

   Marvin's manager data grant from the previous FastLab allows `UPDATE(department_id)` for his direct reports in `HR.EMPLOYEES`. It does not allow that update on Marvin's own employee row. The cross-table manager grant therefore applies to Emma, Charlie, and Dana, but not to Marvin himself.

3. Review the new data grants.

      ```sql
      <copy>
      SELECT grant_name, privilege, object_owner, object_name
        FROM dba_data_grants
       WHERE grant_name IN (
             'PAYSTUBS_SELF_ACCESS',
             'PAYSTUBS_MANAGER_ACCESS')
       ORDER BY grant_name, privilege;
      </copy>
      ```

      | GRANT_NAME | PRIVILEGE | OBJECT_OWNER | OBJECT_NAME |
      |---|---|---|---|
      | PAYSTUBS_MANAGER_ACCESS | SELECT | HR | EMP_PAYSTUBS |
      | PAYSTUBS_SELF_ACCESS | SELECT | HR | EMP_PAYSTUBS |
      {: title="Cross-table data grants"}

## Task 3: Understand the runtime check

When an end user queries `HR.EMP_PAYSTUBS`, Oracle Database evaluates the cross-table relationship at run time.

1. The database checks the child row in `HR.EMP_PAYSTUBS`.
2. The `WHERE` predicate matches the child row to a parent row in `HR.EMPLOYEES`.
3. The database checks whether the end user has the required parent privilege on that parent row.
4. If the parent privilege exists, the child-row privilege applies. If not, the child row is filtered out.

This is hierarchical access propagation. You write the parent access policy once, then child tables inherit access through their relationship to the parent.

Cross-table grants can also form chains. For example, `CUSTOMERS` can authorize `ORDERS`, and authorized `ORDERS` can authorize `ORDER_ITEMS`.

## Task 4: Test as Emma and Marvin

> **Before you begin:** Exit your current DBA session by typing `EXIT` and pressing Enter. This task connects as end users.

### Connect as Emma

1. Connect as Emma using the same authentication method from the prerequisite lab.

      ```sql
      <copy>
      sqlplus emma/Oracle123@pdb1
      </copy>
      ```

2. Confirm Emma's identity.

      ```sql
      <copy>
      SELECT ORA_END_USER_CONTEXT.username FROM dual;
      </copy>
      ```

3. Query the child table with no filter.

      ```sql
      <copy>
      SELECT paystub_id, employee_id, gross_pay, net_pay, tax_withheld,
             deductions, bank_account
        FROM hr.emp_paystubs
       ORDER BY employee_id;
      </copy>
      ```

      | PAYSTUB_ID | EMPLOYEE_ID | GROSS_PAY | NET_PAY | TAX_WITHHELD | DEDUCTIONS | BANK_ACCOUNT |
      |---|---|---|---|---|---|---|
      | 9301 | 3 | 5000.00 | 3600.00 | 1000.00 | 400.00 | xxxxxxx3333 |
      {: title="Emma's paystub"}

   Emma sees only her own paystub. There is no data grant directly to Emma on `HR.EMP_PAYSTUBS`. The row appears because Emma can read the `SSN` column on the matching parent row in `HR.EMPLOYEES`.

### Connect as Marvin

4. Connect as Marvin using the same authentication method from the prerequisite lab.

      ```sql
      <copy>
      sqlplus marvin/Oracle123@pdb1
      </copy>
      ```

5. Query the child table with the same SQL Emma used.

      ```sql
      <copy>
      SELECT paystub_id, employee_id, gross_pay, net_pay, tax_withheld,
             deductions, bank_account
        FROM hr.emp_paystubs
       ORDER BY employee_id;
      </copy>
      ```

      | PAYSTUB_ID | EMPLOYEE_ID | GROSS_PAY | NET_PAY | TAX_WITHHELD | DEDUCTIONS | BANK_ACCOUNT |
      |---|---|---|---|---|---|---|
      | 9201 | 2 | 7291.67 | 5250.00 | 1458.33 | 583.34 | xxxxxxx2222 |
      | 9301 | 3 | 5000.00 | 3600.00 | 1000.00 | 400.00 | |
      | 9401 | 4 | 3958.33 | 2850.00 | 791.67 | 316.66 | |
      | 9501 | 5 | 5416.67 | 3900.00 | 1083.33 | 433.34 | |
      {: title="Marvin's paystubs"}

   Marvin sees four paystub rows: his own row and his three direct reports. He sees his own `bank_account` because `PAYSTUBS_SELF_ACCESS` grants full `SELECT` through Marvin's own parent row. He does not see bank account values for Emma, Charlie, or Dana because `PAYSTUBS_MANAGER_ACCESS` excludes that child column.

6. Try to query only Fiona's paystub.

      ```sql
      <copy>
      SELECT paystub_id, employee_id, gross_pay, net_pay
        FROM hr.emp_paystubs
       WHERE employee_id = 7;
      </copy>
      ```

      ```
      no rows selected
      ```

   Fiona has a paystub row, but Marvin does not have a qualifying parent privilege on Fiona's row in `HR.EMPLOYEES`. The child row is filtered out.

## Task 5 (Optional): Clean up

Run the cleanup as a DBA user or your Deep Data Security administrator.

1. Drop the cross-table data grants.

      ```sql
      <copy>
      DROP DATA GRANT hr.paystubs_manager_access;
      DROP DATA GRANT hr.paystubs_self_access;
      </copy>
      ```

2. Drop the child table.

      ```sql
      <copy>
      DROP TABLE hr.emp_paystubs PURGE;
      </copy>
      ```

## What You Built

You created a child table and two cross-table data grants:

| Component | Purpose |
|---|---|
| `HR.EMP_PAYSTUBS` | Child table related to `HR.EMPLOYEES` by `employee_id` |
| `PAYSTUBS_SELF_ACCESS` | Grants full `SELECT` on child paystub rows when the end user has `SELECT(ssn)` on the matching parent employee row |
| `PAYSTUBS_MANAGER_ACCESS` | Grants `SELECT` on child paystub rows, excluding `bank_account`, when the end user has `UPDATE(department_id)` on the matching parent employee row |
| No `TO` clause | The grantee is resolved from parent-row privileges at run time |
{: title="Lab components"}

The key idea: **child-table access is derived, not assigned.** If parent-row access changes, child-row access changes with it.

## Learn More

* [Oracle AI Database Documentation](https://docs.oracle.com/en/database/)
* [Oracle Deep Data Security Configuration Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/index.html)
* [FastLab: Getting Started with Oracle Deep Data Security](../end-user-data-grants/index.html)
* [FastLab: Identity-Aware Database Access with Microsoft Entra ID and Oracle Deep Data Security](../data-grants/index.html)

## Acknowledgements
* **Author** - Richard C. Evans, Oracle Database Security Product Management, June 2026
* **Contributors** - Roger Wigenstam, Oracle Database Security Product Management
* **Last Updated By/Date** - Richard C. Evans, Oracle Database Security Product Management, June 2026
