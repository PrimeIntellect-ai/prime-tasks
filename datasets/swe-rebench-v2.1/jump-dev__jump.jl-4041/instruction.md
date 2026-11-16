Don't add objective in copy_conflict
```Julia
julia> iis_model, _ = copy_conflict(model);

julia> print(iis_model)
Max 2 x + 1
Subject to
 con : 2 x ≤ -1
 x ≥ 0
```

What's that doing there?
