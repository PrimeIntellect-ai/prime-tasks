New Mutants Found
Displaying up to the first 10 mutants:

units/src/timestamp.rs:38:40: replace Timestamp::to_u32 -> u32 with 0
units/src/timestamp.rs:38:40: replace Timestamp::to_u32 -> u32 with 1
units/src/timestamp.rs:48:37: replace <impl From for u32>::from -> Self with Default::default()

For the complete list, please check the [mutants.out artifact](https://github.com/rust-bitcoin/rust-bitcoin/actions/runs/13743509813).

### Additional contract requirements

The block-time type referenced by the mutants above is publicly named `BlockTime` and lives in `units/src/time.rs` (the file was previously named `timestamp.rs`). The public conversions that must be guarded are:

- `BlockTime::from_u32(t: u32) -> BlockTime` constructs a `BlockTime` holding exactly `t`.
- `BlockTime::to_u32(self) -> u32` returns the inner timestamp value unchanged.
- `impl From<u32> for BlockTime` constructs a `BlockTime` holding exactly the supplied value.
- `impl From<BlockTime> for u32` returns the inner timestamp value unchanged.

Consequently, for every `u32` value `x`, `u32::from(BlockTime::from(x)) == x` and `BlockTime::from(x).to_u32() == x`.
