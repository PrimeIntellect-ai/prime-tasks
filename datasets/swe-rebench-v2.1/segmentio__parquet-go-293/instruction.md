How to make an optional map?
Take the sample below:
```go
type Spans struct {
  Attributes map[string]string
}

s := parquet.SchemaOf(new(RowType))
fmt.Println(s)
```

It prints:
```
message Spans {
  required group Attributes (MAP) {
    repeated group key_value {
      required binary key (STRING);
      required binary value (STRING);
    }
  }
}
```

However, I want the Attributes map to be optional:
```
message Spans {
  optional group Attributes (MAP) {
    repeated group key_value {
      required binary key (STRING);
      required binary value (STRING);
    }
  }
}
```

I try to add a tag, but it makes the value optional, not the map.
```
type Spans struct {
	Attributes map[string]string  `parquet:"Attributes,optional"`
}
```



Could you please teach me how to do it?
