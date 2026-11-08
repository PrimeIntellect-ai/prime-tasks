[FORMATTING] newline after FROM and NULL in IS DISTINCT FROM NULL
**Input data**

Which SQL and options did you provide as input?

```sql
SELECT table1.id FROM table1
LEFT OUTER JOIN table2 ON table2.table1_id = table1.id
WHERE NOT (COALESCE(interview_stage.* IS DISTINCT FROM NULL, FALSE))
```

**Expected Output**

// something like this that shows the `IS DISTINCT FROM NULL` part on a single line
```sql
SELECT
      table1.id
    FROM
      table1
      LEFT OUTER JOIN table2 ON table2.table1_id = table1.id
    WHERE
      NOT (
        COALESCE(
            table2.* IS DISTINCT FROM NULL,
            FALSE
        )
      )
```

**Actual Output**

```sql
SELECT
      table1.id
    FROM
      table1
      LEFT OUTER JOIN table2 ON table2.table1_id = table1.id
    WHERE
      NOT (
        COALESCE(
          table2.* IS DISTINCT
          FROM
            NULL,
            FALSE
        )
      )
```

**Usage**

- How are you calling / using the library? Using it in a test to show a nicely formatted expected output
- What SQL language(s) does this apply to? Postgresql
- Which SQL Formatter version are you using? 12.1.0
