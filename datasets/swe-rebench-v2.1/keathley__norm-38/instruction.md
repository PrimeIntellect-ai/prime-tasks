Proposal to make parameter names in a @contract optional
One currently has to name each parameter in a contract, but the name doesn't have to match those used in the function.

For example:

```elixir
defmodule Test do
  use Norm

  def age(), do spec(is_integer())
  def name(), do: spec(is_binary())
  def greeting(), do: spec(is_binary())

  @contract hello(name :: name(), age :: age()) :: greeting()
  def hello(name, age), do: "Hello #{name}. You are #{age}!"
end
```

(Excuse the "looseness" of the `spec` definitions above; in use, I'd be more explicit with the use of regular expressions.)

In the example above, we have the contract:
```elixir
@contract hello(name :: name(), age :: age()) :: greeting()
```

The repetition, if one is naming specs semantically, can make it a little less readable and a little more error-prone.

We can currently write a slightly cleaner:
```elixir
@contract hello(n :: name(), a :: age()) :: greeting()
```

But we can't do the following, which in retrospect might confuse the intent since we're not ignoring the spec, only the parameter name:
```elixir
@contract hello(_ :: name(), _ :: age()) :: greeting()
```

It gives the following error:
```elixir
** (CompileError) invalid use of _. "_" represents a value to be ignored in a pattern and cannot be used in expressions
```

---
What I'd prefer is an option to write:
```elixir
@contract hello(name(), age()) :: greeting()
```

For me, this more concise notation encourages semantically richer naming of specs that communicate their intent better. Of course, there will be those who abuse the shorthand, but they're the same coders who will have lazy parameter names.

This is perhaps a little more controversial, but since `@contract` must be specified immediately above the function(s) it defines, one could conceivably drop the function name:

```elixir
@contract (name(), age()) :: greeting()
```

Or, if it does look a bit like function currying, which Elixir doesn't support without third-party libraries, the even cleaner:

```elixir
@contract name() :: age() :: greeting()
```

I do copy and paste contracts between functions, and sometimes forget to rename them.

---
Note that I'd still like the option to have parameter names in my contracts. I sometimes like to arrange my contract parameters vertically over several lines. And I often use semi-generic naming.

For example (with the necessary module, spec and schema definitions), this is valid code:

```elixir
@contract complex_image_processing_function(
  poster :: Image.s(),
  stills :: coll_of(Image.s()),
  perceptual_hashes :: coll_of(hash()),
  md5s :: coll_of(hash())
) :: coll_of(Image.s())
def complex_image_processing_function(poster, stills, perceptual_hashes, md5s), do: ...
```

### Additional contract requirements

- A contract may omit the parameter name for any argument and write only the spec, for example `@contract foo(int(), int()) :: int()`. Naming parameters remains supported, for example `@contract foo(a :: int(), int()) :: int()`.
- Modules that `use Norm` expose a public function `__contract__/1`. Calling `__contract__({name, arity})` returns a `%Norm.Contract{}` struct with:
  - `args`: a keyword list of `{parameter_name, spec}` pairs, one per argument in declaration order. When a parameter name is omitted, the generated name is `arg1`, `arg2`, … based on the argument's 1-based position.
  - `result`: the spec declared for the return value.
