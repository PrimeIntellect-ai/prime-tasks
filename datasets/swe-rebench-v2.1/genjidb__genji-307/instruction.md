Panic when running GROUP BY on array value
```
Opened an in-memory database.
Enter ".help" for usage hints.
genji> create table foo;
genji> insert INTO foo (a) VALUES ([1, 2, 3]);
genji> select max(a) from foo group by a;
panic: runtime error: hash of unhashable type msgpack.EncodedArray

goroutine 1 [running]:
github.com/genjidb/genji/document.Stream.Aggregate.func1.1(0xa9b600, 0xc00032a870, 0xa9b600, 0xc00032a870)
        /home/asdine/code/github.com/genjidb/genji/document/iterator.go:297 +0xcd
github.com/genjidb/genji/document.Stream.Iterate.func1(0xa9b540, 0xc0001c6fc0, 0xc0001c6ec0, 0x0)
        /home/asdine/code/github.com/genjidb/genji/document/iterator.go:141 +0x78
github.com/genjidb/genji/database.(*Table).Iterate(0xc00015c6c0, 0xc00032f140, 0x0, 0x0)
        /home/asdine/code/github.com/genjidb/genji/database/table.go:343 +0x1b5
github.com/genjidb/genji/document.Stream.Iterate(0xa97680, 0xc00015c6c0, 0x0, 0xc00032f140, 0xc00011a301, 0xc00032f140)
        /home/asdine/code/github.com/genjidb/genji/document/iterator.go:126 +0x151
github.com/genjidb/genji/document.Stream.Iterate(0xa98200, 0xc000156f00, 0xc00011a400, 0xc000180aa0, 0xc00011a420, 0x0)
        /home/asdine/code/github.com/genjidb/genji/document/iterator.go:131 +0xa2
github.com/genjidb/genji/document.Stream.Aggregate.func1(0xc000156f60, 0xa98200, 0x18)
        /home/asdine/code/github.com/genjidb/genji/document/iterator.go:290 +0xff
github.com/genjidb/genji/document.IteratorFunc.Iterate(0xc000166540, 0xc000156f60, 0xc00005a800, 0x7fd1fab327d0)
        /home/asdine/code/github.com/genjidb/genji/document/iterator.go:45 +0x30
github.com/genjidb/genji/document.Stream.Iterate(0xa981e0, 0xc000166540, 0x0, 0xc000156f60, 0x1, 0xc000156f60)
        /home/asdine/code/github.com/genjidb/genji/document/iterator.go:126 +0x151
github.com/genjidb/genji/document.Stream.Iterate(0xa98200, 0xc000156f40, 0xc00011a420, 0xc00011a430, 0x0, 0x0)
        /home/asdine/code/github.com/genjidb/genji/document/iterator.go:131 +0xa2
github.com/genjidb/genji/cmd/genji/shell.(*Shell).runQuery(0xc000243500, 0xc0002e8120, 0x22, 0x0, 0x0)
        /home/asdine/code/github.com/genjidb/genji/cmd/genji/shell/shell.go:287 +0x19c
github.com/genjidb/genji/cmd/genji/shell.(*Shell).executeInput(0xc000243500, 0xc0002e8120, 0x22, 0x2, 0x3)
        /home/asdine/code/github.com/genjidb/genji/cmd/genji/shell/shell.go:222 +0x1fe
github.com/genjidb/genji/cmd/genji/shell.(*Shell).execute(0xc000243500, 0xc0002e8120, 0x22)
        /home/asdine/code/github.com/genjidb/genji/cmd/genji/shell/shell.go:204 +0x85
github.com/c-bata/go-prompt.(*Prompt).Run(0xc0001f01b0)
        /home/asdine/go/pkg/mod/github.com/c-bata/go-prompt@v0.2.5/prompt.go:84 +0x85f
github.com/genjidb/genji/cmd/genji/shell.Run(0xc0001a3640, 0xc0001a3640, 0x0)
        /home/asdine/code/github.com/genjidb/genji/cmd/genji/shell/shell.go:128 +0x385
main.main.func2(0xc0001c6840, 0xc0001a3600, 0x4)
        /home/asdine/code/github.com/genjidb/genji/cmd/genji/main.go:102 +0x1a5
github.com/urfave/cli/v2.(*App).RunContext(0xc000186480, 0xaa0600, 0xc0001ae030, 0xc0001922a0, 0x1, 0x1, 0x0, 0x0)
        /home/asdine/go/pkg/mod/github.com/urfave/cli/v2@v2.2.0/app.go:315 +0x70d
github.com/urfave/cli/v2.(*App).Run(...)
        /home/asdine/go/pkg/mod/github.com/urfave/cli/v2@v2.2.0/app.go:215
main.main()
        /home/asdine/code/github.com/genjidb/genji/cmd/genji/main.go:108 +0x4dd
```
