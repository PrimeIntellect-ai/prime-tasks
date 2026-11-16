More than one string with trailing backslash
**Describe the bug**

I tried formatting

```sql
select
  *
from
  mytable
where
  mycol_a like 'prefix\_%' escape '\'
  and mycol_b like 'prefix\_%' escape '\'
```

**Expected behavior**

Output exactly the same as input.

**Actual behavior**

```
Error: Parse error: Unexpected "\_%'"
    at E.value (https://unpkg.com/sql-formatter@latest/dist/sql-formatter.min.js:1:34317)
    at E.value (https://unpkg.com/sql-formatter@latest/dist/sql-formatter.min.js:1:41347)
    at I.value (https://unpkg.com/sql-formatter@latest/dist/sql-formatter.min.js:1:30283)
    at Module.SS (https://unpkg.com/sql-formatter@latest/dist/sql-formatter.min.js:1:210009)
    at HTMLTextAreaElement.format (https://sql-formatter-org.github.io/sql-formatter/index.js:50:31)
```

If I add a space after the first `'\'` to `'\ '` it works. If I remove the last `and [etc.]` line then it also works.

**Usage**

- How are you calling / using the library? https://sql-formatter-org.github.io/sql-formatter/
- What SQL language(s) does this apply to? I tried every formatter. This is definitely [valid syntax in Trino](https://github.com/trinodb/trino/blob/91ce0ec5c98a5019f5fb66683bae0ee6c18201b0/core/trino-parser/src/main/antlr4/io/trino/sql/parser/SqlBase.g4#L1147) but also other SQL dialects I think
- Which SQL Formatter version are you using? `latest`. v4.0.0 (with some modifications which shouldn't affect this case) adds a bunch of spaces to the last line `and mycol_b like ' prefix \ _ % ' escape ' \ '`
