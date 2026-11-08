Regression in nested environment paths
In config 0.11, our app used an environment source

```rust
Environment::with_prefix("app").separator("__")
```

Which would match environment vars like `APP_TLS__CERTIFICATE` (into `tls > certificate`).

This no longer works due to the group separator using the specified separator, as opposed to always being `_` https://github.com/mehcode/config-rs/blob/30d87a311929f5382cb4ecd1de62f20d2dddfb86/src/env.rs#L123

This forces me to update my environments to `APP__TLS__CERTIFICATE` which is not the end of the world but it slows adoption of the new version.

I'm not sure on the best solution, but maybe there could be a new `prefix_separator` field. This can be set automatically by the `separator` method too so that it doesn't break any existing 0.12 apps

### Additional contract requirements

- Support a chainable `prefix_separator(s: &str)` setting for the delimiter between the environment prefix and the remaining key path. When no explicit prefix separator is set, `separator(...)` must continue to determine that delimiter, preserving existing 0.12 behavior.
