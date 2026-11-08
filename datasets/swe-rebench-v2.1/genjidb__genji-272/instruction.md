parser.ParseQuery panics due to integer divide by zero
`parser.ParseQuery` panics with the following input and stack trace.

```
SELECT*FROM t LIMIT-0%.2
```

<details>
<summary>Stack trace</summary>

```
panic: runtime error: integer divide by zero

goroutine 1 [running]:
github.com/genjidb/genji/document.calculateFloats(0x90, 0x55c760, 0x6dfec0, 0xa0, 0x55bf20, 0xc0000a7c60, 0xc0000a7c25, 0x0, 0x0, 0x900000c000120300, ...)
        /home/runner/work/genji/genji/genji/document/value.go:491 +0x846
github.com/genjidb/genji/document.calculateValues(0xc000111c90, 0x55c760, 0x6dfec0, 0xa0, 0x55bf20, 0xc0000a7c60, 0x25, 0x0, 0x90, 0x55c760, ...)
        /home/runner/work/genji/genji/genji/document/value.go:359 +0x30e
github.com/genjidb/genji/document.Value.Mod(...)
        /home/runner/work/genji/genji/genji/document/value.go:324
github.com/genjidb/genji/sql/query/expr.modOp.Eval(0xc000111c80, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x40c058, 0x60, ...)
        /home/runner/work/genji/genji/genji/sql/query/expr/arithmeric.go:125 +0x18e
github.com/genjidb/genji/sql/parser.selectConfig.ToTree(0x6a1b14, 0x1, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, ...)
        /home/runner/work/genji/genji/genji/sql/parser/select.go:261 +0x4ed
github.com/genjidb/genji/sql/parser.(*Parser).parseSelectStatement(0xc000111c20, 0x55, 0x0, 0x0)
        /home/runner/work/genji/genji/genji/sql/parser/select.go:63 +0x44d
github.com/genjidb/genji/sql/parser.(*Parser).ParseStatement(0xc000111c20, 0x55, 0x0, 0x0, 0x0)
        /home/runner/work/genji/genji/genji/sql/parser/parser.go:91 +0x8a2
github.com/genjidb/genji/sql/parser.(*Parser).ParseQuery(0xc000111c20, 0x5be780, 0xc0000a6000, 0x0, 0x0, 0x0, 0x0, 0x0, 0x18, 0xc000017860)
        /home/runner/work/genji/genji/genji/sql/parser/parser.go:70 +0x214
github.com/genjidb/genji/sql/parser.ParseQuery(0x5be780, 0xc0000a6000, 0xc000017860, 0x18, 0x0, 0x0, 0x0, 0x0, 0x0, 0xc00006de70, ...)
        /home/runner/work/genji/genji/genji/sql/parser/parser.go:41 +0x117
github.com/genjidb/genji/fuzz.FuzzParseQuery(0x7f55a2ef1000, 0x18, 0x18, 0x3)
        /home/runner/work/genji/genji/genji/fuzz/sqlparser.go:13 +0xe9
go-fuzz-dep.Main(0xc00006df70, 0x1, 0x1)
        go-fuzz-dep/main.go:36 +0x1ad
main.main()
        github.com/genjidb/genji/fuzz/go.fuzz.main/main.go:15 +0x52
exit status 2
```
</details>

Post-mortem: when evaluating `x % y` expression, [HIDDEN] That is, y ∈ (0; 1) would panic.

### Additional contract requirements

- For modulo evaluation with a double dividend `math.MaxInt64 + 1000` and integer divisor `100`, the result must be a double with value `8`.
- Parsing the reported SQL input must complete without panicking.
