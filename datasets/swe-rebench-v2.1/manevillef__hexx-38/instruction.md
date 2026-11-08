Product impl always return 0
If we have an iterator of `Hex` called `hex_iter` then:
```rust
hex_iter.product()
```
will always return `Hex::ZERO`

### Additional contract requirements

- `Hex` implements `std::iter::Product`, providing `product<I: Iterator<Item = Hex>>(iter: I) -> Hex`.
- For a non-empty iterator the result is the multiplicative product of its items, computed with `Hex` multiplication.
- For an empty iterator the result is the multiplicative identity `Hex::ONE`.
-
