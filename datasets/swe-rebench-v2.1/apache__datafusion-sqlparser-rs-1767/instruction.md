Parse MySQL `SET GLOBAL` variables
In addition to `SESSION` and `LOCAL` qualifiers, MySQL allows `GLOBAL` for modifying system variables:

```
mysql> SET GLOBAL max_connections = 1000;
Query OK, 0 rows affected (0.00 sec)
```

sqlparser currently interprets `global` as a variable name and fails to parse:

```
$ echo -n "SET GLOBAL max_connections = 1000;" | cargo run --example cli - --mysql
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.02s
     Running `target/debug/examples/cli - --mysql`
Parsing from stdin using MySqlDialect
2025-01-31T00:44:22.858Z DEBUG [sqlparser::parser] Parsing sql 'SET GLOBAL max_connections = 1000;'...
Error during parsing: ParserError("Expected: equals sign or TO, found: max_connections at Line: 1, Column: 12")
```
