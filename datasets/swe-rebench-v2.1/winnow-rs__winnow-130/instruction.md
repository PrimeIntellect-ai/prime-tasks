`take_while_m_n` is invalid for multi-byte UTF-8 characters
`take_m_n` does:
```rust
    [HIDDEN]
              Ok(input.take_split(index))
            } else {
              Err(Err::Error(Error::from_error_kind(
                input,
                ErrorKind::TakeWhileMN,
              )))
            };
```

while `Input::position` is defined as
```rust
  /// Returns the byte position of the first element satisfying the predicate
  fn position<P>(&self, predicate: P) -> Option<usize>
  where
    P: Fn(Self::Item) -> bool;
```
[HIDDEN]

I see that rust-bakery/nom#913 was previously reported but the 7483885 and rust-bakery/nom#1097 just added the "`Item` count to byte position" conversion but didn't address that it was using a byte position.

The reason the test from rust-bakery/nom#913 is working is the else-clause for when there are more valid elements than `n` (4 is greater than 1), it caps it by `n` (1), making the  `Item` count valid that it passes to `slice_index`.

To show this failing, we need to change `m`, `n`, and the input slightly
```rust
  #[test]
  fn take_while_m_n_utf8() {
    named!(parser<&str, &str>, take_while_m_n!(1, 2, |c| c == 'A' || c == '😃'));
    assert_eq!(parser("A!"), Ok(("!", "A")));
    assert_eq!(parser("😃!"), Ok(("!", "😃")));
  }
```
This fails, with the left-hand side reporting `Ok(("", "😃!")`.  The only reason it doesn't crash is that `slice_index`, when exhausted, returns `self.len()`.

I believe this problem predates rust-bakery/nom#1612

`nom`s issue for this is rust-bakery/nom#1630

### Additional contract requirements

- For multi-byte UTF-8 input, apply the `m` and `n` bounds to the number of input items, not byte positions. A successful parse requires at least `m` consecutive matching items and consumes no more than `n` matching items.
- Do not consume the first nonmatching item.
