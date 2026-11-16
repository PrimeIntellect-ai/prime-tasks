Consider removing the `Self::Error: From<Fut::Error>` bound on `fold`
This bound means that the error type of the inner closure cannot be inferred when it is always `Ok`.

My fold return value must now be:

```rust
Ok::<_, tower_grpc::Error>((summary, Some(point)))
```

All combinators should probably be inspected for such issues.
