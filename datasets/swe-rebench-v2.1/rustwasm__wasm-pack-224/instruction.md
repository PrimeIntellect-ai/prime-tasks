wasm-bindgen dep check should not fail on dep map
I poked around other issues and didn't see any related info, so sorry if I'm missing something here... I was playing around with an existing `wasm-pack`-happy project by enabling [`wasm-bindgen`'s "serde-serialize" feature](https://github.com/rustwasm/wasm-bindgen/blob/f437e06463fb096af04afaa405ad116b2e8f2ef7/src/lib.rs#L187)... everything was all good until I tried rerunning the project through wasm-pack:

```
❯ wasm-pack init -t nodejs
invalid type: map, expected a string for key `dependencies.wasm-bindgen`
Caused by: invalid type: map, expected a string for key `dependencies.wasm-bindgen`
```

Is there anything I can do to work around this?

Happy Cargo.toml:

```toml
[dependencies]
wasm-bindgen = "^0.2"
```

Unhappy Cargo.toml:

```toml
[dependencies.wasm-bindgen]
version = "^0.2"
features = ["serde-serialize"]
```

----

```
❯ rustc --version
rustc 1.29.0-nightly (874dec25e 2018-07-21)
❯ wasm-pack --version
wasm-pack 0.4.1
❯ wasm-bindgen --version
wasm-bindgen 0.2.13
❯ uname -a
# OSX 10.13.5
Darwin sloveless.local 17.6.0 Darwin Kernel Version 17.6.0: Tue May  8 15:22:16 PDT 2018; root:xnu-4570.61.1~1/RELEASE_X86_64 x86_64
```

Wonderful project! TIA!

### Additional contract requirements

- The crate configuration check must fail with an error when the `wasm-bindgen` dependency is declared with a value that is neither a version string nor a table (for example, a boolean or integer).
