MapScan doesn't decode nested documents
[MapScan](https://sourcegraph.com/github.com/genjidb/genji@master/-/blob/document/scan.go#L180:9) should decode the entire document into a `map[string]interface{}`, including nested documents and arrays.

- documents should be decoded into `map[string]interface{}`
- arrays should be decoded into `[]interface{}`

Currently, nested documents are returned as byte slices.
