Boolean flags don't read environment variables
**Describe the bug**
Boolean flags do not read environment variables.

**To Reproduce**
Steps to reproduce the behavior:
Create a command with a boolean flag and try use an environment variable to enable the flag.

**Expected behavior**
It is possible to pass the `env` option to a boolean flag, so boolean flags should take env variables into consideration and check them for truthy values.

### Additional contract requirements

When a boolean flag uses an environment variable, the value `true` must enable the flag when it is not supplied on the command line. A non-truthy value must not enable the flag. Other string spellings for truthy or falsy values are not required.
