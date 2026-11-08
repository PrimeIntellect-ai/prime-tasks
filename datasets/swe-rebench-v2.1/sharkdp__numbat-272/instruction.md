Add logical operators
- Add `&&`, `||` binary operators
- Add `!` unary operator
- Simplify the `examples/binomial_coefficient.nbt` example program by collapsing some layers

### Additional contract requirements

- `&&` and `||` accept Boolean operands, produce Boolean conjunction and disjunction results, and reject non-Boolean operands.
- `!` negates a Boolean and rejects non-Boolean operands.
- In mixed logical expressions, `!` binds more tightly than `&&`, and `&&` binds more tightly than `||`.
