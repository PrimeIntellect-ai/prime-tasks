return Point from user defined function
Currently the user may write:
```
function circ(p=O, color=nothing)
    color !== nothing && sethue(color)
    circle(p, 25, :fill)
    return Transformation(p, 0.0)
end
```
but actually might want to return a `Point` and without an `angle`.

So the user wants to write

```
function circ(p=O, color=nothing)
    color !== nothing && sethue(color)
    circle(p, 25, :fill)
    return p
end
```

I actually fail to think about a usage for returning an `angle` :smile:
