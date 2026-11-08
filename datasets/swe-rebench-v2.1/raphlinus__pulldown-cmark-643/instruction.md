] inside inline code inside link text gets parsed incorrectly if corresponding reference exists
For this input:
```markdown
[`]: xx:

[`]`]
```

It should be parsed like this, since there is no link reference `` `]` ``
```html
<p>[<code>]</code>]</p>
```

But it's currently parsed as a link:
```html
<p><a href="xx:"><code>]</code></a></p>
```

From the [commonmark spec](https://spec.commonmark.org/0.30/#example-341):
> Code span backticks have higher precedence than any other inline constructs except HTML tags and autolinks.

---

Additionally, the `OffsetIter`'s range of this link is only the front part up to the `]`, i.e. the this part:
```text
[`]`]
^^^
```

This is currently causing rustdoc nightly to panic in some cases, see https://github.com/rust-lang/rust/issues/111117.

<details>
<summary>demo program that shows this behavior</summary>

```rust
use pulldown_cmark::{Parser, html};

/// [`]: xx:
///
/// [`]`]
fn main() {
    let text = "\
        [`]: xx:\n\
        \n\
        [`]`]\n\
    ";

    for (event, span) in Parser::new(text).into_offset_iter() {
        println!("{:?}: {:?}", event, &text[span]);
    }

    let mut parsed = String::new();
    html::push_html(&mut parsed, Parser::new(text));
    println!("{parsed}");
}
```

output:
```text
Start(Paragraph): "[`]`]\n"
Start(Link(Shortcut, Borrowed("xx:"), Borrowed(""))): "[`]"
Code(Borrowed("]")): "`]`"
End(Link(Shortcut, Borrowed("xx:"), Borrowed(""))): "[`]"
End(Paragraph): "[`]`]\n"
<p><a href="xx:"><code>]</code></a></p>
```

This shouldn't be parsed as a link in the first place, but even if it is, the range should be `` "[`]`]" ``, not `` "[`]" ``.

If you run `cargo +nightly doc` it crashes.

</details>
