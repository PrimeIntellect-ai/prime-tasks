"protocol Norm.Conformer.Conformable not implemented" errors on incomplete schemas
I've only come across this error when working with lists, but perhaps it's a more general issue when one forgets to write a full schema.

For example:

```elixir
defmodule Movie do
  use Norm

  defstruct directors: [], actors: []

  defmodule Person do
    use Norm

    defstruct name: ""

    def s(),
      do:
        schema(%__MODULE__{
          name: spec(is_binary())
        })
  end

  def s(),
    do:
      schema(%__MODULE__{
        directors: coll_of(Person.s())
      })

  def new(), do: %__MODULE__{}
end
```

When you try:

```elixir
Movie.new() |> conform!(Movie.s())
```

You get the error message:

```
** (Protocol.UndefinedError) protocol Norm.Conformer.Conformable not implemented for [] of type List
```

The "workaround" is to include a schema entry for `actors` in the `Movie` module, alongside the one for `directors`. Beyond being an unhelpful error message, I presume it's a bug in Norm, which has the concept of incremental "speccing".

For reference, a fuller version of the error message is:

```elixir
** (Protocol.UndefinedError) protocol Norm.Conformer.Conformable not implemented for [] of type List.

This protocol is implemented for the following type(s): Norm.Spec.Or, Atom, Norm.Spec.Union, Norm.Schema, Norm.Spec.And, Tuple, Norm.Spec.Collection, Norm.Generator, Norm.Spec, Norm.Spec.Selection, Norm.Spec.Alt
```
