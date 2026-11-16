marshaling byte slice ignores json.Marshaler/encoding.TextMarshaler interfaces
When a codec is created for a byte-slice type at https://github.com/segmentio/encoding/blob/bc545e97dc873711de072cb3246241637958745f/json/codec.go#L80
it ignores the fact that the type could be implementing the `json.Marshaler` or `encoding.TextMarshaler` interfaces. This should be considered in priority, to be compliant with the standard library.

The following playground demonstrates the issue:
https://play.golang.org/p/Bm0d3jsWkZf

The relevant code can be found in the standard library at https://github.com/golang/go/blob/da4d58587e0e4028ea384580053c3c455127e446/src/encoding/json/encode.go#L415
[HIDDEN]

### Additional contract requirements

- When marshaling a byte-slice type that implements `json.Marshaler` or `encoding.TextMarshaler`, honor the implemented interface instead of the default byte-slice encoding. This precedence also applies to nil and non-nil values.
