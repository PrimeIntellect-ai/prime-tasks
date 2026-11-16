Bug with context scoping
While working on #839, I discovered a bug in how the `ParseState` context is being passed around that is causing the `with` tag to not work as intended. Unfortunately, the tests do not currently test whether the context within the tags is isolated and does not affect the context outside of them.

This is most likely causing other issues with context not being properly scoped.

I am working on a PR to simplify how the context is handled and make scoping more explicit.
