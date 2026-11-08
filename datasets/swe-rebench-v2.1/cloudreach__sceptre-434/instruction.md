Improve stack with no outputs error message
Context

The previous error message was KeyError: 'Outputs', which doesn't tell you which stack is the problem.

Done When

A better error message is shown - displaying the offending stack.

### Additional contract requirements

- When a stack that exists has no outputs, attempting to use one of its outputs raises a `DependencyStackMissingOutputError` whose message identifies the offending stack.
