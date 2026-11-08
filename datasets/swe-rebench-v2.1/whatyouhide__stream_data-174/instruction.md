Simple generator for random/constant/unshrinkable things
I can't seem to find a way to make a simple generator for something like `&Ecto.UUID.generate/0`.  Per #38, `bind/2` works I think because the inner generator is recreated each time, so my best guess on implementing that generator is currently

```elixir
# Just picking any generator here
StreamData.integer()
|> StreamData.bind(fn _i -> StreamData.constant(Ecto.UUID.generate()) end)
|> StreamData.unshrinkable()
```

It seems strange to have to build off of another generator for no good reason there.

```elixir
StreamData.constant(Ecto.UUID.generate()) |> Enum.take(10)
```
This doesn't work, as naturally the list simply repeats the generated uuid.

### Additional contract requirements

Provide `StreamData.repeatedly/1`, accepting a zero-arity function and returning a generator. Invoke the function anew for each generated sample, rather than reusing a value computed when the generator is created. Values produced by this generator must not have shrink alternatives.
