Dependency Manager repeats the inquiry for extra dependencies
### Instructions

Add a contract with multiple imports.

### Problem

<img width="861" alt="image" src="https://github.com/onflow/flow-cli/assets/707025/b18ccd2d-01e4-4671-bb7e-956272983f4b">

The same dependency has been asked multiple times (even if it already exists in flow.json or has been answered before).

### Steps to Reproduce

just do it.

### Acceptance Criteria

Already asked or already in the dependency of flow.json, only ask once.

### Context

flow-cli: v1.18.0

### Additional contract requirements

- When showing the deployment inquiry for contract C on emulator, the user-visible log message must contain `C added to emulator deployments`.
