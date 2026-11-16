Library is super fussy about paramater-less functions
A couple of examples come to mind. My concern is more with the error messages than the philosophy behind it.

---
(1) Calling Norm functions without `()`

The following is, of course, fine:

```elixir
"test" |> conform!(spec(is_binary()))
```

But when you drop the parentheses on `is_binary`...:

```elixir
"test" |> conform!(spec(is_binary))
```

you get the cryptic error message:

```elixir
** (ArgumentError) Norm can't build a spec from: is_binary
    (norm) lib/norm/spec.ex:74: Norm.Spec.build/1
    (norm) expanding macro: Norm.spec/1
    iex:8: (file)
    (elixir) expanding macro: Kernel.|>/2
    iex:8: (file)
```

---
(2) One's own functions in modules that use Norm:

In the following code, note that `new` is not written as `new()`:

```elixir
defmodule Movie do
  use Norm

  defstruct title: "The Fly", year: 1986

  def s(),
    do:
      schema(%__MODULE__{
        title: spec(is_binary()),
        year: spec(is_integer())
      })

  def new, do: %__MODULE__{}
end
```

When compiling, I get the cryptic error:

```elixir
** (ArgumentError) argument error
    :erlang.length(nil)
    (norm) lib/norm/contract.ex:166: Norm.Contract.fa/1
    (norm) expanding macro: Norm.Contract.def/2
    lib/movie.ex:13: Movie (module)
```

It does detect the correct line number (13) though.

### Additional contract requirements

- When `conform("1", spec(is_integer and Integer.is_even))` fails, it must return `{:error, [%{input: "1", path: [], spec: "is_integer()"}]}`.
- - When `conform("1", spec(Foo.match?("foo") and is_binary))` fails, it must return `{:error, [%{input: "1", path: [], spec: "Foo.match?(\"foo\")"}]}`.
