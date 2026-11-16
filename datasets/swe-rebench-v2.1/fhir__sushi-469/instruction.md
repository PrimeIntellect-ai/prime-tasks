Set the count on FSH-authored CodeSystems
If SUSHI can determine the count for a FSH-authored CodeSystem, it should set `count`.  The `content` property should probably be considered as SUSHI may not be able to set a valid count for CodeSystems whose content is  not `complete` (e.g., `fragment`).

### Additional contract requirements

- For a `#complete` CodeSystem with a user-specified `^count` that differs from the number of concepts (treating an absent concept list as 0), emit a warning containing `The user-specified ^count (<count>) does not match the specified number of concepts (<number of concepts>).`, substituting the specified count and concept count. Include the source location of the `^count` rule; for a rule in `test.fsh` at line 2, the warning must include `File: test.fsh` and `Line: 2`.
- For a rule in `test.fsh` at line 2, the warning must place the mismatch sentence before `File: test.fsh`, followed by whitespace and then `Line: 2`.
- Do not derive `count` from the concept list when a CodeSystem's `content` is not `complete`.
