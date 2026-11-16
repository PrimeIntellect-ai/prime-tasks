regression: `SET role = 'foobar'` was broken by the latest release
Using a sql keyword as a variable name used to work in previous versions and was broken by the latest release.
This has caused issues downstream like https://github.com/sqlpage/SQLPage/discussions/644

The problem appears with:

```sql
SET role = 'foobar';
```

which is valid SQL (at least in postgres), and which now fails parsing with `ParserError("Expected: identifier, found: =")`
