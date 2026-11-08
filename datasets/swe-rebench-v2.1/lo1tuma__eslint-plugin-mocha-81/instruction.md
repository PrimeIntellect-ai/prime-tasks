Feature Request: allow users to provide variables to protect from `.only`
I'm using `ember-cli-mocha` which provides some functions that build on top of `describe`, such as `describeModule`.  I would love to be able to provide an array of additional things to disallow `.only` from being called.

### Additional contract requirements

For `no-exclusive-tests`, configure additional test-function names through the ESLint `settings` entry `mocha/additionalTestFunctions`. Its value is an array of function-name strings.
