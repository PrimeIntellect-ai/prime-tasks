Warn if an argument is invalid
It would be nice to catch invalid arguments for directives. Seems relatively easy to do. Currently the failure pass silently.

### Additional contract requirements

- An argument name that a directive does not support must trigger a warning that identifies the name, but must not prevent the directive from being processed.
- Supported argument names must not trigger this warning.
