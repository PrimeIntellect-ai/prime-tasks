Custom definition names of `Module`s are not sanitized
## Describe the bug
It is possible to specify a `definitionName` that is not sanitary (as sanitized by `Sanitizer`), which means you can generate invalid SystemVerilog.

## To Reproduce
Define a module with an unsanitary `definitionName` passed to `Module`'s constructor.

## Expected behavior
ROHD sanitizes the definition name so that it generates valid SystemVerilog.

## Actual behavior
The unsanitary definition name is included directly in the generated SystemVerilog.

**Additional context**
Sanitization may as well occur directly within the constructor.
