Passing in null or undefined to compose query throws exception
- [ ] Feature
- [x] Bug

<!--If this is a bug, please include the steps to reproduce the bug-->
## Description
Passing in null or undefined to composeQuery should either return an empty string or should throw a specific error message stating input is required.

Actual:
Cannot read map of undefined.

### Additional contract requirements

- `composeQuery(null)` and `composeQuery(undefined)` must not throw the generic "Cannot read ... of undefined/null" error. They must either return an empty string (`''`) or throw an error whose message states that the input is required.
- `getFlattenedFields` must return the alias (instead of the field name or relationship path) for a relationship field that has an alias.


- If `composeQuery` throws for `null` or `undefined`, the error message must contain `require` (case-insensitively).
