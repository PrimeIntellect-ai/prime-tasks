How to write with nested struct
Hi Team, I'm new to this package and sorry to bother.
I was trying to write a series of data with nested struct like
```golang
type People struct {
    Name string
    Age int
}

type Nested struct {
    P []People
    F string
    GF string
}
```

and here are two issues I met:
1. how write with nested struct ? I tried to write with the following code but failed with "read error: EOF":
```golang
func main() {
	type People struct {
		Name string
		Age  int
	}

	type Nested struct {
		P  []People
		F  string
		GF string
	}
	row1 := Nested{P: []People{
		{
			Name: "Bob",
			Age:  10,
		}}}
	ods := []Nested{
		row1,
	}
	buf := new(bytes.Buffer)
	w := parquet.NewGenericWriter[Nested](buf)
	_, err := w.Write(ods)
	if err != nil {
		log.Fatal("write error: ", err)
	}
	w.Close()

	file := bytes.NewReader(buf.Bytes())
	rows, err := parquet.Read[Nested](file, file.Size())
	if err != nil {
		log.Fatal("read error: ", err)
	}

	for _, row := range rows {
		fmt.Printf("%q\n", row)
	}
}
```

2. can segmentio/parquet-go write partial fields to parquet according to a new struct? It was like I have stored a slice of data with struct
```golang
type Nested struct {
    P []People
    F string
    GF string
}
```
and when I write to parquet I just want to store
```golang
type Nested struct {
    P []People
    F string
    // GF string         ignore GF field
}
```

sorry to bother and wondering if there is a example doc ? Thank you so much

### Additional contract requirements

For the second request, writing the original row values must support omitting `GF` from the Parquet output by supplying a schema without that field. The rows may retain the full `Nested` Go type, including a non-empty `GF`; writing only values of a different Go type that lacks `GF` does not by itself satisfy this requirement. The output schema must omit `GF`, while the remaining row data, including the nested `P` values, is written.
