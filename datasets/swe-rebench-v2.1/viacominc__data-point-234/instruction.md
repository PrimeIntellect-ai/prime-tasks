helpers.createReducer is not exposed
<!--
Thanks for your interest in the project. We appreciate bugs filed and PRs submitted!
Please make sure that you are familiar with and follow the Code of Conduct for
this project (found in the CODE_OF_CONDUCT.md file).

Please fill/un-comment out this template with all the relevant information so we can
understand what's going on and fix the issue.
-->

**Problem description**:

`helpers.createReducer` is not exposed to API

https://github.com/ViacomInc/data-point/blob/cd7701998000a7cff0bca64e494f814293a6d5c3/packages/data-point/lib/index.js#L6-L14

**Suggested solution**:

[HIDDEN]

**Environment**:

- `data-point` version:  2.x

### Additional contract requirements

- The top-level DataPoint API exposes `createReducer`.
- Given a supported reducer definition, `createReducer` returns a reducer that can be passed to `DataPoint.resolve`.
