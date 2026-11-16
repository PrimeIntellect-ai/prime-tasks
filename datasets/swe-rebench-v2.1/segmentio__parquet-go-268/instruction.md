Add ability to set properties on key and value of a Parquet map
Currently when defining a Parquet map:

```
type A struct {
  B map[string]string `parquet:","`
}
```

We don't have the ability to set the properties of the key or value for that map.

One possibility is to add something similar to the following:

```
type A struct {
  B map[string]string `parquet:",key(dict,zstd)"`
}
```

### Additional contract requirements

Properties on a map's key and value must be configurable independently. Value properties use the ordinary options in the map field's `parquet` tag. Key properties may be provided with a `key(...)` option in that tag, as suggested above, or with a `parquet-key` tag. For example, configuring a timestamp on the key must produce a timestamp logical type on the generated key schema, and configuring a timestamp on the value must produce it on the generated value schema.
