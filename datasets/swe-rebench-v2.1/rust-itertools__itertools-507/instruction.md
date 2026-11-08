Allow `iproduct` to be called like `itertools__iproduct!(..)`
Currently (itertools 0.9) it appears as if I have to use the `iproduct` macro like this:

```rust
use itertools::iproduct;
iproduct!(-1..=1,-1..=1,-1..=1,-1..=1)
```

It would be nice to be able to also use it like so:

```rust
itertools::iproduct!(-1..=1,-1..=1,-1..=1,-1..=1)
```

But doing so returns an error like:

```
error: cannot find macro `iproduct` in this scope
  --> src/bin/day17.rs:79:9
   |
79 |         itertools::iproduct!(-1..=1,-1..=1,-1..=1)
   |         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   |
   = note: this error originates in a macro (in Nightly builds, run with -Z macro-backtrace for more info)
```

[HIDDEN]

### Additional contract requirements

- The `iproduct` macro must be callable as `itertools::iproduct!(...)` without a separate `use itertools::iproduct;` import, including invocations with multiple range arguments as shown above.
