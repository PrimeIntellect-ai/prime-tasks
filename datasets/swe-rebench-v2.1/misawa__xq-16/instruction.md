Panics on comparison of booleans
Comparison on booleans panics.

```sh
 $ xq -n 'false < true'
thread 'main' panicked at 'internal error: entered unreachable code', src/intrinsic/comparator.rs:99:17
note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace
```

xq: 0.1.0-d3808e624efc78b26ebd3c464bea59132f83aec8
