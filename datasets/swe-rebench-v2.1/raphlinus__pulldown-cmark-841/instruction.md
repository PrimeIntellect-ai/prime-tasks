[fuzz result] unbalanced parens are parsed as a link title
This markdown should not produce a link:

```markdown
[link]: test (()

[link]
```

The [commonmark.js dingus](<https://spec.commonmark.org/dingus/?text=%5Blink%5D%3A%20test%20(()%0A%0A%5Blink%5D>) does this right. As the spec sayeth:

https://spec.commonmark.org/0.30/#link-reference-definitions

> A [link reference definition](https://spec.commonmark.org/0.30/#link-reference-definition) consists of a [link label](https://spec.commonmark.org/0.30/#link-label), optionally preceded by up to three spaces of indentation, followed by a colon (:), optional spaces or tabs (including up to one [line ending](https://spec.commonmark.org/0.30/#line-ending)), a [link destination](https://spec.commonmark.org/0.30/#link-destination), optional spaces or tabs (including up to one [line ending](https://spec.commonmark.org/0.30/#line-ending)), and an optional [link title](https://spec.commonmark.org/0.30/#link-title), which if it is present must be separated from the [link destination](https://spec.commonmark.org/0.30/#link-destination) by spaces or tabs. No further character may occur.

https://spec.commonmark.org/0.30/#link-title

> A [link title](https://spec.commonmark.org/0.30/#link-title) consists of either
> - a sequence of zero or more characters between straight double-quote characters ("), including a " character only if it is backslash-escaped, or
> - a sequence of zero or more characters between straight single-quote characters ('), including a ' character only if it is backslash-escaped, or
> - a sequence of zero or more characters between *matching parentheses* ((...)), including a ( or ) character only if it is backslash-escaped.

<details>

```rust
"[+]:\\\n(()" -> [
]
```

Events from commonmark.js:

```rust
"[+]:\\\n(()" -> [
  Start(Paragraph)
    Text(Boxed("(()"))
  End(Paragraph)
]
```
