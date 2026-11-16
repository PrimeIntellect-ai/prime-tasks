FromMeta parsing doesn't error on unrecognized literals in attribute list
FromMeta doesn't error in all cases that unexpected tokens end up in the attribute list.

It doesn't error in the case that a string literal is in the attribute list. For example:
```rust
#[myattribute(myfield = "export", "randomliteral")]
```

Parsing the attribute list will error if it sees a field that is anticipated, but not for `"randomliteral"` which it will ignore.

cc @jonjove
