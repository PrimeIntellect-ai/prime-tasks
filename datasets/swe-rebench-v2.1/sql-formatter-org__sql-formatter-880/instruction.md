SQLServer errors
**Describe the bug**
This is similar to this closed issue: https://github.com/sql-formatter-org/sql-formatter/issues/700. I'm unable to format a valid SQLServer statement. Using the [demo](https://sql-formatter-org.github.io/sql-formatter/), there appears to be no language selection that doesn't error.

**Expected behavior**
Output should be formatted.

**Actual behavior**
Got this error:
```
Error: Parse error: Unexpected "[Contact] " at line 1 column 6.
This likely happens because you're using the default "sql" dialect.
If possible, please select a more specific dialect (like sqlite, postgresql, etc).
```

**Usage**
```javascript
import { format } from 'sql-formatter';
let sql_string = "WITH [Contact] AS (SELECT [ContactID], [FirstName], [LastName] FROM [dbo].[Contact])";
format(sql_string, { language: 'sql' })
```

- What SQL language(s) does this apply to?
SQLServer

- Which SQL Formatter version are you using?
```
sql
```

I'm on 15.3.1 so I figured opening a new issue was prudent.

### Additional contract requirements

The Transact-SQL (SQL Server) dialect must accept ODBC date literals of the form
`{d'YYYY-MM-DD'}` (for example `{d'2024-01-01'}`) and preserve them verbatim in the
formatted output. Bracket-quoted identifiers (for example `[Contact]`, `[dbo].[Contact]`)
must also be preserved verbatim.
