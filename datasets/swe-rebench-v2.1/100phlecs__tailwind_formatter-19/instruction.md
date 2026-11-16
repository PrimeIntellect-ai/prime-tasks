Formatter inserts incorrect `}`
The first time I tried the formatter in one of our projects it worked. The second time I got an FunctionClauseError `no function clause matching in Phoenix.LiveView.HTMLFormatter.to_tree/4`.

It turns out that the first run of the tailwind formatter formats the following

```elixir
    <div class={"h-6 " <> if @active, do: "bg-white", else: "bg-red"}></div>
```

to

```elixir
    <div class={"h-6"} <> if @active, do: "bg-white", else: "bg-red"}></div>
```

And this is invalid code because of the inserted `}` :-)

### Additional contract requirements

The formatter must also handle nested interpolated strings inside attribute
expressions. Formatting

```elixir
<.img src={~p"/images/#{"card-#{@card.brand}.svg"}"} />
```

must not raise an error and must leave the expression unchanged.


- For the malformed input cases with a missing final quote or an invalid inline Elixir expression, formatting must either raise `ArgumentError` or return the input unchanged.
