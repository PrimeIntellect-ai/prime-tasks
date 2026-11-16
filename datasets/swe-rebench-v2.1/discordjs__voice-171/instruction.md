Refactor to use AbortController in entersState
- Should up minimum Node.js version to v16
- Be backwards-compatible - if a time is provided in entersState, create an AbortController from that

### Additional contract requirements

- Declare the package's minimum supported Node.js version as v16 in `package.json`'s `engines.node` field.
- For a numeric timeout, create an `AbortController` whose signal aborts after the supplied duration. A wait for a state not yet reached remains pending until that timeout expires, then rejects.
- A wait resolves with its target when that target reaches the requested state before the timeout, and also resolves when the target is already in that state.
