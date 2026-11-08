Use `unsafe` blocks in `unsafe fn`s
`cxx::bridge` generates code incompatible with the  `unsafe_op_in_unsafe_fn` lint. Since this is a useful lint and it's likely to become an error in the future, `cxx::bridge` should wrap unsafe ops in `unsafe` blocks always.

Right now it's impossible to use it with `forbid(unsafe_op_in_unsafe_fn)` and requires explicit `allow()` attributes with `deny(...)`
