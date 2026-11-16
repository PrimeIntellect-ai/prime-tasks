[fuzz result] invalid HTML entities are parsed
According to the spec:

> [Decimal numeric character references](https://spec.commonmark.org/0.30/#decimal-numeric-character-references) consist of `&#` + a string of 1–7 arabic digits + `;`. A numeric character reference is parsed as the corresponding Unicode character. Invalid Unicode code points will be replaced by the REPLACEMENT CHARACTER (`U+FFFD`). For security reasons, the code point `U+0000` will also be replaced by `U+FFFD`.

That implies that `&#00000000;`, which has eight zeroes, is invalid. Yet pulldown-cmark accepts it.

<details>

Events from pulldown-cmark:

```rust
"v&#00000000;v\n" -> [
  Start(Paragraph)
    Text(Boxed("v�v"))
  End(Paragraph)
]
```

Events from pandoc:

```rust
"v&#00000000;v\n" -> [
  Start(Paragraph)
    Text(Boxed("v&#00000000;v"))
  End(Paragraph)
]
```

Events from commonmark.js:

```rust
"v&#00000000;v\n" -> [
  Start(Paragraph)
    Text(Boxed("v&#00000000;v"))
  End(Paragraph)
]
```

</details>
