Type checker sees arguments of function calls in reversed order
If you have a function that accepts multiple arguments of different types
```elixir
fn foo(a1: Type1, ..., an: TypeN)
```
and you call it, you'll get
```Elixir
{:error, "Undefined function: <module>.foo(TypeN, ..., Type1) in module <module>"}
```
<br>

**e.g.**
```Elixir
fn foo(a: Int, b: String) : Int do
  a
end

fn bar : Int do
  foo(5, "a")
end
```
results in
```elixir
{:error, "Undefined function: sandbox.foo(String, Int) in module sandbox"}
```
<br>

**Note:** the call's AST (below) looks good (the order of the args is preserved) so I suppose the problem lies in the type checker

```elixir
{:call, {:foo, _}, [{:integer, _, 5}, {:string, _, ["a"]}], nil}
```
