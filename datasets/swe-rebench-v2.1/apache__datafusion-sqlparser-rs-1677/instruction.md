Clickhouse: Support underscore in numbers
See https://clickhouse.com/docs/en/sql-reference/syntax#numeric

```sql
SELECT 10_000_000
```

```
[
    Word(
        Word {
            value: "SELECT",
            quote_style: None,
            keyword: SELECT,
        },
    ),
    Whitespace(
        Space,
    ),
    Number(
        "10",
        false,
    ),
    Word(
        Word {
            value: "_000_000",
            quote_style: None,
            keyword: NoKeyword,
        },
    ),
]
