View hint
Currently `subset` takes `view=` which is a hint that may be ignored. I don't like the idea of ignoring keyword argument values, so I'm considering the issue. On Slack some approaches were discussed,

One option is to rename `view` to `viewhint`.

Another option is the `view` could be a hint supplemented by a second argument `force` or `strict`. I normally prefer that `force`/`strict` arguments be explicit about what exactly is being forced, for example `forceviewoption`.

But then once that's the situation, it seems odd to have both `view` and an option for saying "I really mean it" rather than just passing either `viewhint` or `view` with the latter being enforced. The enforced `view` argument could be added in a separate PR, which would make this option very similar to the first.

Therefore I propose renaming `view` to `viewhint`. Then in the future if users so desire, add a `view` argument that would be enforced. They would combine according to the following rules:

```jl
@match (view, viewhint) begin
(true, _) => enforce true
(false, _) => enforce false
(nothing, true) => prefer true
(nothing, false) => prefer false
end
```

An alternative future implementation could define a `subsetview` function if desired.
