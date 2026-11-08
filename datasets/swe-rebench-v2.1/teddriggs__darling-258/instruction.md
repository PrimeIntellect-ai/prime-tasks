Field-level default should take path without quotation marks
The [HIDDEN] type was never updated to accept a path in the right-hand side. This means that `#[darling(default = path_to_fn)]` doesn't work, while `#[darling(default = "path_to_fn")]` does. We should allow the quotation-free form.

### Additional contract requirements

- A field-level default specified with a bare path must be accepted and used as the explicit default.
