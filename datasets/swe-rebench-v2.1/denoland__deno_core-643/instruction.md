Enable Temporal API by default
Working on https://github.com/denoland/deno/pull/22134 I had to pass a V8 flag on startup to enable Temporal API (I then conditionally remove it from global scope on startup if appropriate unstable is not provided). The problem is that Temporal won't be available in the snapshot and will probably cause a slowdown on startup.

We should enable Temporal by default in `deno_core` [HIDDEN]

Then a simple test that checks for presence of `Temporal` global will be needed:
```rust
runtime.execute_script("test.js", r#"if (typeof Temporal === "undefined") throw new Error()"#)
```

### Additional contract requirements

- Temporal must be enabled by default in `deno_core`, so the `Temporal` global is available without an external startup flag.
