How to ignore a field when write parquet to file
Just want to ask is there any way to ignore a field when write to parquet file like what encoding/json package did when marshal/unmarshal:
```
// Field is ignored by this package.
Field int `json:"-"`

// Field appears in JSON as key "-".
Field int `json:"-,"`
```

ref: https://pkg.go.dev/encoding/json#Marshal

P/s: Thank, this project is great.

### Additional contract requirements

- A struct field tagged `parquet:"-"` is omitted from the Parquet schema and its values are not written to the Parquet file.
- A struct field tagged `parquet:"-,"` is retained in the Parquet schema with the field name `-`.
