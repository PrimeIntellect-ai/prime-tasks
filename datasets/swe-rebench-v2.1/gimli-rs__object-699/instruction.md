Please add support for 32-bit SPARC
The `object` crate has already support for 64-bit SPARC (`Sparc64`) while support for 32-bit SPARC (`Sparc`) is missing.

Since `rustc` itself has support for both 32- and 64-bit SPARC, it would be great if `object` could support both flavors as well.

I haven't had the time to write the code myself yet as I just discovered that the missing support in `object` is the reason why `rustc` currently cannot be built for `sparc-linux-unknown-gnu`, so I'm just opening the issue for the time being in the hope that someone might beat me to it.
