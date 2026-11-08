Mergo is not overriding destination map key with empty value with WithOverwriteWithEmptyValue
When trying to merge two maps, mergo does not respect`WithOverwriteWithEmptyValue`.

Eg:

```
destination := map[string]string{"a": "valueOfA"}
source := map[string]string{"b": "valueOfB", "c": "valueOfC"}

mergo.Merge(&destination, &source, mergo.WithOverwriteWithEmptyValue)
```

Current output:
`map[a:valueOfA b:valueOfB c:valueOfC]`

Expected output:
`map[b:valueOfB c:valueOfC]`
Since "a" should be discarded with provided `WithOverwriteWithEmptyValue` option.

Playground: https://go.dev/play/p/kR8K-G7sPPt
