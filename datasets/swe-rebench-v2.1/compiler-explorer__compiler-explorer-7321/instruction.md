[BUG] Compiler type "AWS" breaks
Putting an `AWS` magic compiler name in the compiler list breaks in the client with a missing `compiler.disabledFilters` (patched up elsewhere).

Either kill the AWS support, or fix.
