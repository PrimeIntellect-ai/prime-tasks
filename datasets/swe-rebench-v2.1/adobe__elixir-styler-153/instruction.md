alias lifting: bug when referring to nested module of an alias
## Versions

* Elixir: use `elixir --version`
* Styler: use `mix deps | grep locked | grep styler`

## Example Input

```elixir
# Given
alias Foo.Bar.Baz

Baz.Bop.Boom.wee()
Baz.Bop.Boom.wee()

# Get:
alias Baz.Bop.Boom
alias Foo.Bar.Baz

Boom.wee()
Boom.wee()
```

[HIDDEN]

### Additional contract requirements

- When styling a nested module reference whose leading name resolves to an existing alias, preserve its original module resolution. In the example, both calls must continue to refer to `Foo.Bar.Baz.Bop.Boom`, not to an unrelated `Baz.Bop.Boom` module.
