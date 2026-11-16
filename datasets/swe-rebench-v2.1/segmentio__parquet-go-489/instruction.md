[Bug] parquet.readFile only reads 1024 rows
This file (zipped parquet file):
[debug.zip](https://github.com/segmentio/parquet-go/files/10542463/debug.zip) has more than 1024 rows (around 9K).

But if I read it using the following code:

```
type RowType struct {
	Name string `parquet:",optional"`
	Data []byte `parquet:",optional"`
}

rows, err := parquet.ReadFile[RowType](file)
```

and print out the number of rows, I only see that there are 1024 rows.
Tools like the `pandas` library from Python don't have this issue.
