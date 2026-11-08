define `inf, sup` etc. for non-intervals
What do you think, would it make sense to define, e.g.

```julia
[HIDDEN]
```

etc.

I think they could be useful to write generic code that works both for intervals and non-intervals

### Additional contract requirements

- For a non-interval real scalar `x`, `inf(x)`, `sup(x)`, and `mid(x)` return `x` unchanged; `diam(x)` and `radius(x)` return zero.
