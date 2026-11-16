@required vs required
The codemod is currently converting `required` arguments to `required` attributes, instead of `@required` arguments. This might be fine for `<Input>` (is it?), but certainly not for **all** components.

The same applies for `placeholder` vs. `@placeholder`.

The codemod also does something similar for `class`, but I suspect in that case it should be fine.
