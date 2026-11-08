Support whitespace control
Not sure when they added that but we should support this: https://shopify.github.io/liquid/basics/whitespace/

### Additional contract requirements

Whitespace control is expressed with a hyphen placed next to a Liquid delimiter:

- `{{-` removes all whitespace immediately preceding an output expression, and `-}}` removes all whitespace immediately following it.
- `{%-` removes all whitespace immediately preceding a tag, and `-%}` removes all whitespace immediately following it.

When a delimiter has no adjacent hyphen, the surrounding whitespace is preserved verbatim. Whitespace control is available through the existing `parse`/`render` API; no new public interfaces are introduced.
