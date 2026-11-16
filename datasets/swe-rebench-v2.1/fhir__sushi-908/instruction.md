SUSHI should automatically populate `url` for appropriate #definition instances
If an `Instance` has `Usage: #definition` and is a type that has a `url` field intended to represent the definition's canonical, then SUSHI should automatically set the `url` like it does for `Profile`, `Extension`, `CodeSystem`, and `ValueSet` definitions.  Otherwise the user must manually type in the full URL, which can be brittle if the overall canonical of the IG changes.

### Additional contract requirements

- If a `url` has been explicitly assigned to a `#definition` instance, SUSHI must preserve it rather than replace it with the generated canonical URL; for example, `http://someDifferentCanonical.org/testInstance` remains unchanged.
