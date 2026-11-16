Compile errors after actix-web-codegen v4.2.0 -> v4.2.1
After running `cargo update`, with the ONLY update being `actix-web-codegen v4.2.0 -> v4.2.1` (I updated all other ones one-by-one using `cargo update -p <...>`), i gets compilation errors of the [martin](https://github.com/maplibre/martin) project:

```
error: unexpected token
  --> martin/src/srv/server.rs:95:12
   |
95 |     wrap = "middleware::Compress::default()"
   |            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
...
```

## Steps to Reproduce (for bugs)

1. `git clone https://github.com/maplibre/martin.git`
2. `cd martin`
3. `git reset --hard b5902aa`
4. `cargo build`  <-- this should pass
5. `cargo update -p actix-web-codegen` <-- this will show updating `v4.2.0 -> v4.2.1`
6. `cargo build`  <-- this will now fail with lots of errors

## Context

<!--- How has this issue affected you? What are you trying to accomplish? -->
<!--- Providing context helps us come up with a solution that is most useful in the real world -->

## Your Environment

- Linux Mint
- Rust Version (I.e, output of `rustc -V`): `rustc 1.72.0 (5680fa18f 2023-08-23)`
- Actix Web Version: `4.4.0`

### Additional contract requirements

- A route macro must accept a `wrap` string containing a Rust expression, including a method call such as `middleware::Compress::default()`, rather than rejecting it as an unexpected token.
