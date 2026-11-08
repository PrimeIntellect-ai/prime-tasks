Memory leak
The following snippet causes unexpectedly high memory usage:

```go
func BenchmarkParseSubject(b *testing.B) {
	for n := 0; n < b.N; n++ {
		_, err := ParseSubjectStringToRawDERBytes("DF=#6666666666665006838820013100000746939546349182108463491821809FBFFFFFFFFF")
		if err == nil {
			b.Fatal("expected error, but got none")
		}
	}
}
```

Run with:

```console
go test -bench=. -benchmem ./pkg/util/pki/...
```

Before this change:

```text
goos: darwin
goarch: arm64
pkg: github.com/cert-manager/cert-manager/pkg/util/pki
BenchmarkParseSubject-12              58          20398892 ns/op        1665740367 B/op       58 allocs/op
```
