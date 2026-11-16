class assign should accept a list
You should be able to say

```elixir
div class: ["some class", @class] do
end
```

You can already use keyword lists to conditionally render classes, but a plain list should work as well.
