proposal: Introduce temp-env for better env test
Hi, I saw our unit tests failed randomly like:

- https://github.com/mehcode/config-rs/runs/5805369539?check_suite_focus=true
- https://github.com/mehcode/config-rs/runs/6010922223?check_suite_focus=true

How about introduce [temp-env](https://github.com/vmx/temp-env) for better env test?

```rust
temp_env::with_vars(
    vec![
        ("FIRST_VAR", Some("Hello")),
        ("SECOND_VAR", Some("World!")),
    ],
    || {
        // Run some code where `FIRST_VAR` is set to `"Hello"` and `SECOND_VAR` is set to
        // `"World!"`.
    }
);
```

If it looks good to you, I'm willing to start a PR for it. :laughing:

### Additional contract requirements

- Provide a top-level function `temp_env::with_var(key, value, f)` that sets the environment variable named by `key` to the value inside `Some(...)` for the duration of the closure `f`, and restores that variable's previous state once the closure returns.
- Provide a top-level function `temp_env::with_vars(vars, f)` that accepts an iterable of `(key, value)` pairs and sets each named environment variable to its `Some(...)` value for the duration of the closure `f`, restoring every variable's previous state once the closure returns.
