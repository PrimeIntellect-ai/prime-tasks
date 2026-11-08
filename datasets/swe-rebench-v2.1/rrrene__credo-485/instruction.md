Credo.Check.Readability.VariableNames dont work on function parameter variables
### Environment

* Credo version: 0.8.10
* Erlang/Elixir version: Erlang/OTP 18 [erts-7.3] / Elixir 1.4.2

### What were you trying to do?
suppose we have code like this
```
def some_func(notSnakeCase) do
  notSnakeCase + 1
end
```

### Expected outcome
Code Readability.
Variable names should be written in snake_case.


### Actual outcome
nothing

### Additional contract requirements

`Credo.Check.Readability.VariableNames` must report a variable that is not written in snake_case whenever that variable is bound, not only for parameters of named functions. The binding positions that must be covered are:

- parameters of named functions (`def`/`defp`)
- parameters of anonymous functions (`fn`)
- variables bound in `case` clause patterns
- variables bound in `catch` clause patterns
- variables bound in `receive` clause patterns
- variables bound in `with` clause patterns
- variables bound by comprehension generators (`for`/`<-`) and variables bound within comprehension expressions (for example by a `=` match or a `case` in the `do` body)
