Overwrite constants and functions in the REPL
It's a very frequent use case to go "up arrow" and change something in a let/fn definition.

### Additional contract requirements

- A function defined before a constant is redefined must continue to use the earlier value captured by that function. For example, after `let x = 1`, `fn f() = sin(x)`, and `let x = 1 m`, evaluating `f()` must output `0.841471`.
