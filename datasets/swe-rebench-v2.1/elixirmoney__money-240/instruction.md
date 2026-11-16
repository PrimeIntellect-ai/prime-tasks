Money.parse doesn't handle scientific notation
I consider this a bug in our code, but I wanted to document it here, just so people are aware.

We had some code where Decimals were being represented in scientific notation, e.g.

```elixir
value = Decimal.new("0")
divisor = :math.pow(10, 2) |> Decimal.from_float() # Decimal.new("100.0")
value = Decimal.div(value, divisor) # Decimal.new("0E+1")
```

That itself isn't a problem. The problem happens with some Money.parse code like this:

```elixir
Money.parse!("#{value}", currency)
```

Which is effectively doing this:

```elixir
Money.parse!("0E+1", :USD) # %Money{amount: 100, currency: :USD}
```

So converting to a string before parsing Money is resulting in $1 when the original input was 0, or more specifically 0E+1.

Passing the Decimal directly to Money works just fine.

```elixir
Decimal.new("0E+1") |> Money.parse!(:USD) # %Money{amount: 0, currency: :USD}
```

I'm not sure if this should be "fixed" -- is Money supposed to be able to parse scientific notation? Maybe it just needs to be called out as not supported?

### Additional contract requirements

`Money.parse/3` must support strings in scientific notation. The exponent
marker may be a lowercase `e` or an uppercase `E`, and may be followed by an
optional `+` or `-` sign. The parsed value must equal the numeric value of
the scientific-notation string converted to the currency's sub-units.

For example:

    Money.parse("0E+1", :USD) == {:ok, %Money{amount: 0, currency: :USD}}
    Money.parse("1000.0e1", :USD) == {:ok, %Money{amount: 1_000_000, currency: :USD}}
    Money.parse("1000.0E-1", :USD) == {:ok, %Money{amount: 10_000, currency: :USD}}
    Money.parse("0.5e-1", :USD) == {:ok, %Money{amount: 5, currency: :USD}}
