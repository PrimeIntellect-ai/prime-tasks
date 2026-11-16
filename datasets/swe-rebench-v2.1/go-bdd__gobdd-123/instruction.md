Add before/after step callbacks
**Is your feature request related to a problem? Please describe.**
I have a repetitive set up and teardown code for many step functions.

**Describe the solution you'd like**
- `gobdd.WithBeforeStep(func(ctx gobdd.Context))`
- `gobdd.WithAfterStep(func(ctx gobdd.Context))`

**Describe alternatives you've considered**
Adding a "decorator" to my step functions.

**Additional context**
It would be nice if the default context contains current feature and scenario references.
