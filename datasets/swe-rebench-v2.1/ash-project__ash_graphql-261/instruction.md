The default error handler should not be applied when a custom error handler is defined at domain level
The ability to specify an error handler at the resource level [was recently added in this PR](https://github.com/ash-project/ash_graphql/pull/253), a nice addition.

This introduced an unintended side-effect, such that when an error handler has been specified at the domain level, the default error handler was also being applied at the resource level.

I will submit a PR for this fix.
