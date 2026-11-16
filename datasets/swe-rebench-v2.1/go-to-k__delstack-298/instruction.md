[Feature] throws error if a stack with XxxInProgress is specified
Originally not displayed in interactive mode, it still does not generate an error when the stack name is directly specified.

### Additional contract requirements

- For a stack named `test` in `DELETE_IN_PROGRESS`, return an error with the exact message `OperationInProgressError: Stacks with XxxInProgress cannot be deleted, but DELETE_IN_PROGRESS: test`.
