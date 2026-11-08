Unknown type with `option_env` macro
```Rust
let x = option_env!("CI");
   //^ {unknown}
```
The strange part is that if I use `inline macro` assist, it will work (after manually replacing `$crate` with `core`):
```Rust
let x = core::option::Option::None:: < &str>;
  //^ Option<&str>
```

### Additional contract requirements

- When the environment variable is unset, `option_env!` must expand to `::core::option::Option::None:: < &str>`.
