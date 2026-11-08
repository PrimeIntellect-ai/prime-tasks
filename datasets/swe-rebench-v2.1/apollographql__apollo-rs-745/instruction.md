Regression in parser 0.7.3: empty object values no longer parse
<!--
 Please fill out each section below, otherwise, your issue may be closed.
This info allows apollo-rs maintainers to diagnose (and fix!) your issue as
quickly as possible.

Before opening a new issue, please search existing issues:
https://github.com/apollographql/apollo-rs/issues
-->

## Description

Describe the issue that you're seeing.

### Steps to reproduce

Assume a schema with an input object:
```graphql
input Input {
  optional: Boolean
}
type Query {
  field(arg: Input): Int
}
```

And a query like this with an empty object:
```graphql
{
  field(arg: {})
}
```

### Expected result

Should parse without errors.

### Actual result

```
Error: syntax error: expected Object Value
   ╭─[/dev/fd/11:8:15]
   │
 8 │   field(arg: {})
   │               ┬
   │               ╰── expected Object Value
───╯
```

### Environment

- `apollo-rs` crate: `apollo-parser`
- Crate version: 0.7.3
