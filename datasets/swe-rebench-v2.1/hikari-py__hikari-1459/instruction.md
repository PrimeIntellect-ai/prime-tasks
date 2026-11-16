Add option to supress optimization warning message
### Summary

The warning introduced by #1431 can be annoying in some context (for example code analysis that needs runtime evaluation, like [slotscheck](https://slotscheck.readthedocs.io/en/latest/)).

I assume there may be some other use cases for wanting to disable the warning (dev platform running without optimization, etc)

### Why is this needed?

Other features can be disabled iirc, like the check for update call or the banner. More choice seems better in that case.

### Ideal implementation

Using the same mechanism as banner deactivation?

### Checklist

- [X] I have searched the issue tracker and have made sure it's not a duplicate. If it is a follow up of another issue, I have specified it.

### Additional contract requirements

- `GatewayBot.__init__` and `RESTBot.__init__` accept the `suppress_optimization_warning` keyword, defaulting to `False`. Setting it to `True` suppresses the optimization warning during construction.
- The optimization warning is emitted only when Python is running without optimization and warning suppression has not been requested.
