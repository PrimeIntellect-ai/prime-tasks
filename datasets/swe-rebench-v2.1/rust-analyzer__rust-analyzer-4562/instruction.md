Assist: replace anonymous lifetime with a named one
before:

```rust
impl Cursor<'_<|>> {
    fn node(self) -> &SyntaxNode {
        match self {
            Cursor::Replace(node) | Cursor::Before(node) => node,
        }
    }
}
```

after:

```rust
impl<'a> Cursor<'a> {
    fn node(self) -> &SyntaxNode {
        match self {
            Cursor::Replace(node) | Cursor::Before(node) => node,
        }
    }
}
```

### Additional contract requirements

- The assist is identified by the id `change_lifetime_anon_to_named`.
- The assist applies to an anonymous lifetime `'_` written in an `impl` header and to an anonymous lifetime `'_` written in a function definition. In both cases it replaces the anonymous lifetime with a fresh named lifetime and adds that lifetime parameter to the enclosing `impl` or function definition.
- The new lifetime name must not conflict with any lifetime parameter already declared on the enclosing `impl` or function. When a function lifetime being named corresponds to a unique input reference whose lifetime is elided, that input reference must use the same new lifetime.
- The assist is not offered when the cursor is not on an anonymous lifetime `'_` (for example, when the cursor is on a function name or on an already-named lifetime).


- For the function input `fn my_fun(x: X<'_>) {}`, the assist must produce `fn my_fun<'a>(x: X<'a>) {}`.
