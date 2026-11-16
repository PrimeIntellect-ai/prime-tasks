Misleading Error When Header Name Used in BEGIN/END
When `@"Header_Name"` is used in `BEGIN` and `END` blocks, the error message is misleading, e.g.

```
$ goawk --csv  -H 'BEGIN { print @"HEADER" }' /dev/null
@ only supported if header parsing enabled; use -H or add "header" to INPUTMODE
```

### Additional contract requirements

- The error message must be exactly `no field names for @; use -H or add "header" to INPUTMODE, and use "getline" first if in BEGIN`.
