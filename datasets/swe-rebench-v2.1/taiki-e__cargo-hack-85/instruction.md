Intelligently exclude redundant items in powerset
Consider the following case (the actual crate doesn't matter; I just tested it on an empty crate).

```toml
[features]
std = ["alloc"]
alloc = []

```

I then perform `cargo hack check --feature-powerset --exclude-all-features` (I've inquired about true necessity of the latter flag elsewhere). This is the output:

```none
info: running `cargo check --no-default-features` on tmp (1/4)
    Finished dev [unoptimized + debuginfo] target(s) in 0.00s
info: running `cargo check --no-default-features --features alloc` on tmp (2/4)
    Finished dev [unoptimized + debuginfo] target(s) in 0.00s
info: running `cargo check --no-default-features --features std` on tmp (3/4)
    Finished dev [unoptimized + debuginfo] target(s) in 0.00s
info: running `cargo check --no-default-features --features alloc,std` on tmp (4/4)
    Finished dev [unoptimized + debuginfo] target(s) in 0.01s
```

Presumably it would be possible to determine from `Cargo.toml` that `std` relies on `alloc`, and as such `alloc,std` is redundant (because `std` is already in the powerset).

### Additional contract requirements

When generating a feature powerset, do not run a combination that includes a feature together with any feature it directly declares as a dependency; that combination is redundant.
