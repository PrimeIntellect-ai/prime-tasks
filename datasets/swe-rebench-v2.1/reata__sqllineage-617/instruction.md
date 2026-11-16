False negative for Scalar Subquery used in Function
**Describe the bug**

Great package, thanks for your work! I've found that for this specific case which our users sometimes write, the lineage does not detect the table reference.

I've check that the parsing via sqlfluff works well.

**SQL**
Paste the SQL text here. For example:
```sql
Create table hello_world AS

SELECT EXPLODE(SEQUENCE(
   TO_DATE((SELECT MIN(my_date) FROM my_table),
TO_DATE((SELECT MAX(my_date) FROM my_table),
INTERVAL 1 DAY
)) AS result

```

**To Reproduce**
*Note here we refer to SQL provided in prior step as stored in a file named `test.sql`*

CLI (Command Line Interface): provide the command you're calling and the output.

Command:
```shell
sqllineage -f test.sql --dialect=sparksql
```
```
Statements(#): 1
Source Tables:

Target Tables:
    <default>.hello_world
```

**Expected behavior**
A clear and concise description of what you expected to happen, and the output in accordance with the `To Reproduce` section.

```
Statements(#): 1
Source Tables:
    <default>.my_table

Target Tables:
    <default>.hello_world
```

**Python version (available via `python --version`)**
 - 3.10.12

**SQLLineage version (available via `sqllineage --version`):**
 - 1.5.3

**Additional context**
Add any other context about the problem here.
