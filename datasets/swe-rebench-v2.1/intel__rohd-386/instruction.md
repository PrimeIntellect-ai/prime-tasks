Implement a shorthand for case statements
### Motivation

Sometimes it's desirable to assign/create some signal based on some condition, similar to a `mux`, but there is more than one case to consider.  The current easy options could be either a chain of `mux`s, which implies priority, or building a `Case` in a `Conditional`, which is a little heavy-weight for a simple scenario.

It would be nice to have some automation that creates a `Conditional` and `Case`, optionally with the usual set of settings like `unique`.

### Desired solution

A function which builds a `Conditional` and `Case` statement with some simple set of inputs.  Probably it should only be capable of applying to a single signal (i.e. one output, like `mux`).  For more complex scenarios, people can just create the full thing themselves.

### Alternatives considered

_No response_

### Additional details

_No response_

### Additional contract requirements

- The public shorthand function is named `cases`. Its first positional argument is the selector signal and its second positional argument is the case mapping (case value to result).
- `cases` produces one result signal based on the supplied selector and case mapping; it is intended for a single output, not as a multi-output replacement for a full `Conditional`.
- Callers can supply customary Conditional settings, including uniqueness; `cases` accepts an optional named `conditionalType` setting including `ConditionalType.unique`.
