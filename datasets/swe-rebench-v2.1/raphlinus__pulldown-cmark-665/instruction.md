Indented table rendering as text
I'm not sure whether to call this a bug or not, as from my quick scan of the spec, I didn't find anywhere where it allows or disallows indenting a table.

Considering that pulldown-cmark allows for indented code blocks, then I assume intended tables should also be valid.

```rust
use pulldown_cmark::{html, Options, Parser};

// Notice the 2 spaces before the pipes
let text = "
  | A   | B   |
  | --- | --- |
  | 1   | 2   |

  ```rust
  println!("Foo Bar");
  ```
";

let mut options = Options::empty();
options.insert(Options::ENABLE_TABLES);
let parser = Parser::new_ext(text, options);

let mut out = String::new();
html::push_html(&mut out, parser);
println!("{}", out);
```

Which outputs the following:

```html
<p>| A   | B   |
| --- | --- |
| 1   | 2   |</p>
<pre><code class="language-rust">println!(&quot;Foo Bar&quot;);
</code></pre>
```

While I expected the following:

```html
<table><thead><tr><th>A</th><th>B</th></tr></thead><tbody>
<tr><td>1</td><td>2</td></tr>
</tbody></table>
<pre><code class="language-rust">println!(&quot;Foo Bar&quot;);
</code></pre>
```

Here's the same table indented with 2 whitespace rendered here on GitHub:

  | A   | B   |
  | --- | --- |
  | 1   | 2   |

It also renders how I'd expect in VSCode's Markdown preview:

![image](https://github.com/raphlinus/pulldown-cmark/assets/17464404/964a1155-b7fb-4881-8285-0beb1317df69)
