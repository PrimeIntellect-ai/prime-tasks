Consider implementing DoubleEndedIterator for Chain
We may sometimes want errors that are printed inside-out from lowest level to highest.

```rust
for e in error.chain().rev() {
    println!("{}", e);
}
```

This may requires some buffering but that's fine, the caller would be doing it anyway in this situation.
