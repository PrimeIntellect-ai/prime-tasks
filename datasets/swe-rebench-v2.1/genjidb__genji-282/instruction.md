Panic on SELECT with LIMIT min(0)/max(0)
`parser.ParseQuery` panics with the following input and stack trace

```
SELECT * FROM e LIMIT min(0)
SELECT * FROM t OFFSET x(*)
```

<details>
<summary>Stack trace</summary>

```
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x18 pc=0x50ec01]

goroutine 1 [running]:
[HIDDEN]
github.com/genjidb/genji/sql/parser.(*Parser).parseSelectStatement(0xc0001200f0, 0x55, 0x0, 0x0)
	/home/runner/work/genji/genji/genji/sql/parser/select.go:63 +0x44d
github.com/genjidb/genji/sql/parser.(*Parser).ParseStatement(0xc0001200f0, 0x55, 0x0, 0x0, 0x0)
	/home/runner/work/genji/genji/genji/sql/parser/parser.go:91 +0x8a2
github.com/genjidb/genji/sql/parser.(*Parser).ParseQuery(0xc0001200f0, 0x5bd440, 0xc00001c0a8, 0x0, 0x0, 0x0, 0x0, 0x0, 0x1a, 0xc00011e080)
	/home/runner/work/genji/genji/genji/sql/parser/parser.go:70 +0x214
github.com/genjidb/genji/sql/parser.ParseQuery(0x5bd440, 0xc00001c0a8, 0xc00011e080, 0x1a, 0x0, 0x0, 0x0, 0x0, 0x0, 0xc000043e70, ...)
	/home/runner/work/genji/genji/genji/sql/parser/parser.go:41 +0x117
github.com/genjidb/genji/fuzz/sqlparser.Fuzz(0x7f58e832d000, 0x1a, 0x1a, 0x3)
	/home/runner/work/genji/genji/genji/fuzz/sqlparser/fuzz.go:13 +0xe9
go-fuzz-dep.Main(0xc000043f70, 0x1, 0x1)
	go-fuzz-dep/main.go:36 +0x1ad
main.main()
	github.com/genjidb/genji/fuzz/sqlparser/go.fuzz.main/main.go:15 +0x52
```
</details>

### Additional contract requirements

- Parsing either reported SELECT input must not panic.
