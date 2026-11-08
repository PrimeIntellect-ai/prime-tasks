Export type check function separately from reducer helpers
**Problem description**:

We export type check functions (`isString`, `isNumber`, etc) in the same object as the reducer helpers. However, these are just plain functions whereas the reducer helpers generate a "reducer stub":

https://github.com/ViacomInc/data-point/blob/master/packages/data-point/lib/helpers/helpers.js#L19

**Suggested solution**:

Functions that return a "stub" should be exported in a single object, and the type check functions should be exported in a separate object (something like `DataPoint.typeCheckFunctions`?).

Another solution is to just stop exporting these functions completely, because they're already used internally for creating the `inputType` and `outputType` reducers. These functions have not technically been released yet, so it might be good to keep them internal for now and export them later if that becomes necessary.
