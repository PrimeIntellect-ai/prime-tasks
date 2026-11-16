Tests fail because of a date without time is used, do we need to support that?
Example test:
```rust
    assert_eq!(v!("2001-02-03"), filters!(escape, date(2001, 2, 3)));
```
