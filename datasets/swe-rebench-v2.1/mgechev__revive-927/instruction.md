Supporting multiple expressions for import-alias-naming
In my initial PR about adding [`import-alias-naming`](#881 ) we agreed to have only one expression. However, I'm now not able to easily solve the following limitation:

- allow all alphanumeric aliases with optional digits and have a length at least 1 symbol (i.e. `^[a-z][a-z0-9]*`)
- disallow `^v\d+$` aliases (e.g. `v1`)
- disallow `^v\d+alpha\d+$` aliases (e.g. `v1alpha1`)

In my PR I assumed that golang supports negative lookahead. Unfortunately, my assumption was wrong (as well as there's no support for positive lookahead, also in regex there's no general support for logical `AND`). Do you think, we can revise our decision and allow multiple rules that will be combined by logical `AND`? @chavacava

I can submit a PR with an update (it will be backwards compatible).

### Additional contract requirements

The rule must continue to accept its existing single-expression configuration. To configure the allow and deny constraints together, an argument object may provide `allowRegex` and `denyRegex` expressions. Each provided constraint is enforced, so an alias must satisfy the allow expression and must not match the deny expression. A constraint omitted from the object is not applied. The allow constraint must permit lowercase aliases formed from a lowercase letter followed by lowercase letters or digits; the deny constraint must reject aliases matching either `^v\d+$` or `^v\d+alpha\d+$`.
