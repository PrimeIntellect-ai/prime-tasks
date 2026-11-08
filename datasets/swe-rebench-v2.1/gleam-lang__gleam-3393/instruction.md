Print correct syntax for "Inexhaustive patterns" diagnostic, relative to current module
<!--
Gleam is post-v1, so breaking changes are not possible.

Any new addition to the language itself needs to enable something that is not possible in Gleam today, and solve existing pain-points.

For anything other than trivial and uncontroversial additions please make a GitHub discussion before making an issue. https://github.com/gleam-lang/gleam/discussions/categories/ideas-suggestions
-->
At the moment, this doesn't use the current environment, and just uses type names. The first step to implementing #2957 is to make the error message use the environment to print types

### Additional contract requirements

Missing patterns in an inexhaustive case diagnostic must use constructor syntax that is valid relative to the current module.
