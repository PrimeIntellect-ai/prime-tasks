Bug/quirk: newline inconsistencies in argument list
It seems odd that these are inconsistent, especially since trace and debug are both five letter words:

```rust
use log::{debug, trace};

pub fn main() {
    trace!(
        "get some longer length in here yes yes {} {}",
        "hello",
        "world"
    );
    debug!(
        "get some longer length in here yes yes {} {}",
        "hello", "world"
    );
}
```

Notice the newline present in the `trace` arguments, but not in the `debug` arguments. Other functions seem to follow the same format as the former; perhaps this is something specific with `debug`? Not sure why that would be :shrug:

Versions tested:
- stable: `rustfmt 1.6.0-stable (a28077b 2023-12-04)`
- nightly: `rustfmt 1.7.0-nightly (3d0e6be 2023-12-21)`

### Additional contract requirements

- For this example, keep the `trace!` arguments on separate lines with rustfmt version One. With rustfmt version Two, format them as `"hello", "world"` on one line, matching `debug!`.
