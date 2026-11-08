Display 1-dimensional IntervalBox more clearly
```
julia> X = IntervalBox(-∞..∞)
[-∞, ∞]

julia> X[1]
[-∞, ∞]
```
These two should be differentiated in the output.
