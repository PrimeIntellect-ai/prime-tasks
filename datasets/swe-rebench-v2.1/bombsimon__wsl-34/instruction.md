Separate case blocks and other blocks for whitespaces
Blocks cannot start or end with a whitespace. I think this is a very reasonable rule except for maybe the possibility to end a `case` block with a whitespace. I'm open to the idea to at least have this configurable and maybe even as the default since this can actually improve readability and mark where the next case starts. For this to be reasonable it's important to ensure this **does not** apply to the last `case` since that would actually mena the ending of the `switch` block and not the `case` block.

```go
[token] {
    // Can't be a whitespace here
    fmt.Println("...")
    // Can't be a whitespace here
}

switch {
// Can't be a whitespace here
case 1:
    // Can't be a whitespace here
    fmt.Println("...")
    // Can't be a whitespace here - should it be possible?
case 2:
    // Can't be a whitespace here
    fmt.Println("...")
    // Can't be a whitespace here - should it be possible?
case 3:
    // Can't be a whitespace here
    fmt.Println("...")
// Can't be a whitespace here
}
```

### Additional contract requirements

The opt-in is the `Configuration.AllowCaseTrailingWhitespace` setting. When enabled, it allows whitespace after a case body only when another case clause follows. It does not allow whitespace after the final case, at the start of a block, or at the end of other block types. When disabled (the default), whitespace after a case body remains disallowed.
