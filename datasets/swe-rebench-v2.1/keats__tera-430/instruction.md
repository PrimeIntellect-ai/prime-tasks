Support removing whitespace around expressions
I had some html like this:

```html
<li><a class="p-category"
  href="{{ tag_url }}">
  {{ tag }}
</a></li>
```
This produces a space that is underlined because the whitespace is included.

![Screen Shot of link with trailing whitespace underlined](https://user-images.githubusercontent.com/2229184/60851527-1a133980-a1b9-11e9-9ffe-4c390952333c.png)

Removing the spaces in the template removes the trailing whitespace.

```html
<li><a class="p-category"
  href="{{ tag_url }}">{{ tag }}</a></li>
```

![Screen Shot of link with trailing whitespace removed](https://user-images.githubusercontent.com/2229184/60851537-25666500-a1b9-11e9-801e-15956d58e0d3.png)

Since whitespace removal for statements is supported using `{%-` and `-%}`, could a similar operator for expressions be added? In my case the whitespace wasn't hard to remove manually, but it seemed like a missing feature.

### Additional contract requirements

- Expressions accept the alternate delimiters `{{-` and `-}}` in addition to `{{` and
  `}}`, requesting removal of the whitespace immediately before and/or after the
  expression, mirroring `{%-` and `-%}` for statements.
- The parsed form of a `{{ ... }}` expression is the public enum variant
  `Node::VariableBlock(WS, Expr)` in `src/parser/ast.rs`: the first field holds the
  whitespace-trimming flags and the second field holds the parsed expression.
- `WS` is a public struct in `src/parser/ast.rs` with public boolean fields `left` and
  `right`. For a variable block, `left` is `true` when the opening delimiter is `{{-`
  and `false` otherwise, and `right` is `true` when the closing delimiter is `-}}` and
  `false` otherwise.
- `WS::default()` returns a `WS` whose `left` and `right` are both `false`.
