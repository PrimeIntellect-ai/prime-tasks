feature: Add Skip() to Decoder
**Is your feature request related to a problem? Please describe.**

It can be useful to skip decoding a CBOR data item as discussed in comments for issue https://github.com/fxamacker/cbor/issues/362.

**Describe the solution you'd like**

Add Skip() to the decoder to skip next data item.

**Describe alternatives you've considered**

As mentioned by @fxamacker
>  Until I add a Skip feature, a less efficient way is to decode the messages you want to skip to cbor.RawMessage. cbor.RawMessage copies data item into a byte slice without parsing the data item.

```go
var throwAway cbor.RawMessage
err := decodoer.Decode(&throwAway)
```

### Additional contract requirements

`Decoder.Skip()` must consume exactly the next complete CBOR data item without producing a decoded value, leaving subsequent items available. It must return nil on success and a non-nil error if it cannot skip a complete item, including when input is exhausted, invalid, incomplete, or the underlying reader fails. Skipping must keep the decoder's byte-count reporting accurate.
