Add a start-up check for minimum node and npm versions
### Problem

Currently, the user is not warned if their node/npm version is outdated and doesn't meet the minimum requirements.

### Solution

Add a start-up check for the node/npm version.

### Alternatives

_No response_

### Additional contract requirements

- The start-up version check is provided by a method `checkNodeAndNpmVersions()` on the `InitState` class. It takes no arguments and returns a boolean: `true` when the installed Node.js and npm versions both meet the minimum requirements, and `false` otherwise.
- When the installed Node.js or npm version is below its minimum requirement, the check emits a warning through the application's logger.
