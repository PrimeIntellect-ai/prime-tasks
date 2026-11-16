Could not find `convert` in `core` when using `ensure!` with a conflicting module called `core` in scope
```
error[E0433]: failed to resolve: could not find `convert` in `core`
   --> meridian-graphics/src/shader/user_uniform.rs:940:17
    |
940 | /                 ensure!(is_valid_glsl_identifier(name), InvalidUniformBlockFieldIdentifier {
941 | |                     uniform_block_name,
942 | |                     field_name: name
943 | |                 });
    | |___________________^ could not find `convert` in `core`
    |
    = note: this error originates in a macro (in Nightly builds, run with -Z macro-backtrace for more info)
```
Looks as if the issue is that it considers `core::convert` to be an ambiguous import; writing `use core::convert` in the same source file raises an error that it isn't sure which module to use. [HIDDEN]

### Additional contract requirements

- `ensure!` must work when invoked from a caller that has a module named `core` in scope.
