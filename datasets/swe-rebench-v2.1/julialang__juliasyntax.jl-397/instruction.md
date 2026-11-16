better error message for missing comma.
When missing a `,` in a list or function args, the error message currently says "expected `)`" when the real problem is the missing comma. Should the error message be updated to add that as a possibility? (examples where this comes up are `+(1, 2 3)` and `[1, 2 3]`)
