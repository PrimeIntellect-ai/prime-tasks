add configuration to the validation to enable or disable named validations
**Is your feature request related to a problem? Please describe.**

There isn't a way to enforce a `strict` mode where the process definition is valid according to the ASL definition and doesn't contain any extension elements like a cloud flare deployment function call.

It would also be nice to disable one or more validations. The primary example of this is disabling the path expression checks. There's value in knowing the basic flow of the step function is valid without having to implement every expression. It's also possible that the expressions could be checked elsewhere in the build by another tool and the check in this lib is therefore redundant.

**Describe the solution you'd like**

Provide a config to enable/disable some of the checkers.

### Additional contract requirements

- The validator is the default export of the module `src/validator`. It accepts a state machine definition and a `ValidationOptions` object: `validator(definition: StateMachine, options: ValidationOptions)`. It returns an object with `isValid` (boolean), `errors` (an array of validation errors) and `errorsText(separator?: string)` (a helper returning a formatted string of error messages).
- `ValidationOptions` is exported from the module `src/types`. It is an immutable configuration object with the readonly boolean properties `checkPaths` and `checkArn`. When `checkPaths` is true, path-expression formats are validated; when false, path-expression checks are skipped. When `checkArn` is true, ARN formats are validated; when false, ARN checks are skipped.
