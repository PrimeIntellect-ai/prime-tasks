hcl-edit: hardcoded newline for Body
`hcl-edit` roundtrip on `Body`:

- "`foo = \"bar\"`" => "`foo = \"bar\"\n`" (0 != 1 newline)
- "`foo = \"bar\"\n`" => "`foo = \"bar\"\n`" (1 == 1 newline)
- "`foo = \"bar\"\n\n`" => "`foo = \"bar\"\n\n`" (2 == 2 newlines)

For the first case I would expect there to be no newline in the result.

There seems to be a static newline here
https://github.com/martinohmann/hcl-rs/blob/b92d3d49920683c83bf70008c8c6f832c0cf5481/crates/hcl-edit/src/encode/structure.rs#L12 and something is eating up a newline in the parser
