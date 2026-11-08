Macro expansion referencing the core crate is not hygienic
If you declare a module with the name `core` in a file that uses `Snafu` derive macro, compilation fails with a bunch of errors like the following:

```
error[E0433]: failed to resolve: could not find `convert` in `core`
  --> src/lib.rs:40:17
   |
40 | #[derive(Debug, Snafu)]
   |                 ^^^^^ could not find `convert` in `core`
   |
   = note: this error originates in a derive macro (in Nightly builds, run with -Z macro-backtrace for more info)
```
