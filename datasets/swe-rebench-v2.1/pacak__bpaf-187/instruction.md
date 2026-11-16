Fallback is not documented in usage
Following the example here: https://github.com/pacak/bpaf/blob/4f64f34b2370b30b3ec98872f5ba1a936a6a9e81/examples/multiple_fallback.rs

If I have something like:

```rust
use bpaf::Bpaf;
use once_cell::sync::Lazy;

pub static CONFIG: Lazy<Config> = Lazy::new(|| Config {
    http_port: 3000,
});

#[derive(Clone, Debug, Bpaf)]
#[bpaf(options, version)]
pub struct Config {
    /// Listening port of HTTP server
    #[bpaf(long, env("APP_HTTP_PORT"), fallback(CONFIG.http_port))]
    pub http_port: u16,
}
```

Expected:

```
        --http-port <ARG>                [env:APP_HTTP_PORT: N/A]
                                         Listening port of HTTP server
                                         [default: 3000]
```

Actual:

```
        --http-port <ARG>                [env:APP_HTTP_PORT: N/A]
                                         Listening port of HTTP server
```

### Additional contract requirements

The `[default: ...]` line in the expected output above is produced by the opt-in
`display_fallback` annotation. The example field must be annotated as
`#[bpaf(long, env("APP_HTTP_PORT"), fallback(CONFIG.http_port), display_fallback)]`
so that the fallback value is formatted with `Display` and appended after the
description in `--help`. A `debug_fallback` annotation behaves the same way but
formats the value with `Debug`. Without `display_fallback` or `debug_fallback`
the fallback value is not rendered in `--help`.
