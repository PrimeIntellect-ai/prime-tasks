[ArrayString] Infallible constructor to fill inner array
Some libraries like `hex` or `bs58` expect a pre-filled buffer to operate on but `ArrayString` does not have an infallible constructor to create a fully filled inner array with "whatever".

For example, the following made use of `from_byte_string` to make everything work as expected:

```rust
let mut buffer = ArrayString::from_byte_string(&[b' '; SOME_LEN]).unwrap();
let len = bs58::encode(some_data).into(&mut buffer[..]).unwrap_or_default();
buffer.truncate(len);
```

So do you mind me providing a PR to create something like `ArrayString::new_filled()`?

### Additional contract requirements

Add a public method `ArrayString::<CAP>::zero_filled()` on `arrayvec::ArrayString` that takes no arguments and returns an `ArrayString<CAP>` whose contents are exactly `CAP` ASCII NUL (`\0`) characters, so that its reported length equals `CAP`.
