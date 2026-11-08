IntSet::remove_range() subtract with overflow
Minimal test case:

```rust
let mut set = IntSet::<u32>::empty();
set.remove_range(0..=u32::MAX);
```

Using the range `0..=u32::MAX - 512` works but any greater end range fails. Initializing the set with `all()` succeeds.

The overflow occurs here: https://github.com/googlefonts/fontations/blob/a52dbf59cda0aa16909d0af93fe74c518278a085/int-set/src/bitset.rs#L110

@garretrieger
