Support float segments without the need to add the `float` option
Right now we can already specify int segments and string segments without having to explicitly annotate them with `:int` or `:utf-8`: `<<1, "abc">>`. But we can't do the same with floats: `<<1.2>>` is an error. Since it's unambiguous it would be nice to not have to write `<<1.2:float>>` and it would be consistent with the other types of segment allowed in a bit array expression/constant/pattern

### Additional contract requirements

- Using an unannotated float segment in an expression, constant, or pattern must infer a required Gleam version of 1.10.0. If the project's Gleam version range allows an earlier version, emit an `Incompatible gleam version range` warning at the float literal containing the exact text `This requires a Gleam version >= 1.10.0` and this explanation:

The ability to omit the `float` annotation for float segments was
introduced in version v1.10.0. But the Gleam version range specified in
your `gleam.toml` would allow this code to run on an earlier version like
v1.0.0, resulting in compilation errors!
Hint: Remove the version constraint from your `gleam.toml` or update it to be:

    gleam = ">= 1.10.0"
