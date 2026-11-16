Environment::with_prefix() doesn't use custom separator.
At https://github.com/mehcode/config-rs/blob/master/src/env.rs#L81
```rust
        let prefix_pattern = match self.prefix {
            [HIDDEN]
            _ => None,
        };
```
"_" is appended by default. Shouldn't the custom separator be appended if it exists instead?

### Additional contract requirements

- When a custom separator is configured, use it after the environment prefix when recognizing and removing that prefix from environment-variable keys.
