Make function names in `chalk_ir` more uniform
Right now, the naming of function names in `chalk_ir` is a little bit non-uniform. For example:,
* `Substitution` has `from` and `from_fallible` for an `IntoIterator`, `from1` for a single, and `empty` for nothing
* `Binders` has `new` for a given `VariableKinds` and `empty` for no bound vars
* `VariableKinds` has `from` and `from_fallible` for an `IntoIterator`, `new` for nothing, and no `from1`
* `CanonicalVarKinds` is similar to `VariableKinds`
* `Goals` is also similar to the above two

Additionally `Substitution` uses `parameters`, `Binders` doesn't have a way to access the inner `Binders`, and the others use `as_slice`.

This is honestly a bit of a pain point since I always seem to use the wrong function name.

<!-- TRIAGEBOT_START -->

<!-- TRIAGEBOT_ASSIGN_START -->

<!-- TRIAGEBOT_ASSIGN_DATA_START$${"user":"nathanwhit"}$$TRIAGEBOT_ASSIGN_DATA_END -->

<!-- TRIAGEBOT_ASSIGN_END -->
<!-- TRIAGEBOT_END -->

### Additional contract requirements

- `VariableKinds`, `CanonicalVarKinds`, and `Goals` use `empty` to construct an empty collection.
- `VariableKinds` and `CanonicalVarKinds` each provide `from1` to construct a collection containing one value.
- `Substitution` exposes its parameter slice through `as_slice`.
- `Binders` exposes the bound-variable collection it holds through its public API.
