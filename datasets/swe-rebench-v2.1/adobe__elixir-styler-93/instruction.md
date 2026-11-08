Delete pathless aliases (`alias Foo`)
There's no reason to use `alias` with a root-level module name. If we see that, we can just nix the node.

## Example Input

```elixir
assert_style """
alias unquote(Foo)
alias Foo
alias Bar, as: Bop
alias __MODULE__
""",
"""
alias __MODULE__
alias Bar, as: Bop
alias unquote(Foo)
"""
```
