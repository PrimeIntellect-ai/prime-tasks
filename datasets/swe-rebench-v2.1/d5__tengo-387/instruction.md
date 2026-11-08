Runtime panic on self assignment
The following Tengo script panics at run time:

a := a.foo

This likely because the compiler wrongly considers a to be defined after the := . A should only be considered defined in the next statement.

### Additional contract requirements

- Referencing the variable being defined inside its own initializer is a compile-time error, not a runtime panic. The compiler reports `Compile Error: unresolved reference 'a'` at the position of the reference (for `a := a.foo`, at `test:1:6`).


- For `a := a`, report exactly `Compile Error: unresolved reference 'a'\n\tat test:1:6`.
