Typo in macro definition
PR #2429 added support for AMS log-like symbols.
There is a typo in one of the macro definitions:
```
defineMacro("\\injlim", "[HIDDEN]");
```
The name should start with `inj`, not `int`.
The corresponding test contains the same typo.
