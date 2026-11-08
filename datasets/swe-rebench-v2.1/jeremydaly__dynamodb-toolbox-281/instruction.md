[v0.4.0 Typescript] $append and $prepend not supported to update a list attribute
Tested version : v0.4.0-alpha.2

Issue :
`$append` and `$prepend` are [used in the library](https://github.com/jeremydaly/dynamodb-toolbox/blob/676a42f510bbd7ca0e6598a65d0eeab730784425/src/classes/Entity.ts#L1547), but are not defined in `UpdateItem` Typescript type.

Suggestion :
Add `$append` and `$prepend` [HIDDEN].

### Additional contract requirements

- The `UpdateItem` TypeScript update shape must accept `$append` and `$prepend` as operators for list-attribute updates without type errors.
