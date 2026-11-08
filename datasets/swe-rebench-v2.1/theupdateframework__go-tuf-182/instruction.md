Migrate from github.com/tent/canonical-json-go as it is archived
This project is archived and hasn't been updated in the last 9 years. This is a risk. `json` parsing and marshaling is hard and could have potential issues.

https://github.com/theupdateframework/go-tuf/blob/52193a283c302acaeb39bf8045292815abc568c6/sign/sign.go#L4

https://github.com/tent/canonical-json-go

### Additional contract requirements

- Canonical JSON encoding must be provided by `github.com/secure-systems-lab/go-securesystemslib/cjson` through its `EncodeCanonical(v interface{}) ([]byte, error)` function, which encodes a value to canonical JSON and returns a non-nil error if the value cannot be encoded.
