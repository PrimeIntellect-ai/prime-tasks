Return type i64, u64, and u32 should be converted to REALSXP
While we now can use `use_try_from = true` for type-checking, `TryFrom` is implemented one-way (R to Rust), if I understand correctly

I'm wondering what should happen in this case.

``` r
rextendr::rust_function(r"(
fn f() -> i64 {
  i64::MAX
}
)",
  patch.crates_io = list(`extendr-api` = list(git = "https://github.com/extendr/extendr")),
)
#> ℹ build directory: '/tmp/RtmpR1VmHe/file161681b33c70a'
#> ✓ Writing '/tmp/RtmpR1VmHe/file161681b33c70a/target/extendr_wrappers.R'.

f()
#> [1] -1
```

<sup>Created on 2021-07-23 by the [reprex package](https://reprex.tidyverse.org) (v2.0.0)</sup>

### Additional contract requirements

- Returning a Rust `i64`, `u32`, or `u64` value from an extendr function, or converting such a value with `Robj::from`, must produce an R double vector (type `"double"`).
- The numeric value must be preserved in full: for example `i64::MAX`, `i64::MIN`, `u64::MAX`, and `u32::MAX` must read back as their exact value converted to a double, not as a truncated or wrapped number.
