Chainging return type of `INSERT`
Current
```rust
Payload::Insert(Vec<Row>)
```

Expected
```rust
Payload::Insert(usize)
```

Let's simply return a number of inserted rows.
