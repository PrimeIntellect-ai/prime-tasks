Empty lines in where-clause
I would expect the empty line between the `T: std::fmt::Debug` and `T: std::fmt::Display` lines to be removed by rustfmt, but it isn't:
```rust
fn foo<T>(_: T)
where
    T: std::fmt::Debug,

    T: std::fmt::Display,
{
}
```
At least not by the `rustfmt 1.5.1-stable (69f9c33d 2022-12-12)` version.

I'm sorry if it is a duplicate, but I haven't been able to find any related issues.

<!-- TRIAGEBOT_START -->

<!-- TRIAGEBOT_ASSIGN_START -->

<!-- TRIAGEBOT_ASSIGN_DATA_START$${"user":"naosense"}$$TRIAGEBOT_ASSIGN_DATA_END -->

<!-- TRIAGEBOT_ASSIGN_END -->
<!-- TRIAGEBOT_END -->

### Additional contract requirements

The removal of the empty line between where-clause predicates applies to the Version Two (`version = "Two"`) formatting style. Under the Version One (`version = "One"`) formatting style, the empty line between where-clause predicates is preserved.
