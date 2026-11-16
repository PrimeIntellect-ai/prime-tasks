Incorrect colon indicator scanning
**Describe the bug**

The scanner emits a colon indicator token when a map value of type string starts with a colon and appears at the document's second-to-last index (e.g., `a: :a`). Although this is a rare case, it causes the panic described in #479. This ongoing parsing operation with these tokens leads to a panic.

**To Reproduce**

```go
tokens := lexer.Tokenize("a: :a")
for _, t := range tokens {
  fmt.Printf("%q %v %v\n", t.Value, t.Indicator, t.CharacterType)
}
//"a" NotIndicator Miscellaneous
//":" BlockStructure Indicator
//":" BlockStructure Indicator
//"a" NotIndicator Miscellaneous
```

**Expected behavior**

We expected to get three tokens: key + colon + value.
Instead, we received: key + colon + colon + value.

**Version Variables**
 - Go version: 1.23.2
 - go-yaml's Version: master branch
