linkaxes! is asymmetric
Zooming on the first axis propagates to the others but zooming on the third does not. Is it intended that `linkaxes!` behave in this asmmetric way?

```jl
using WGLMakie

fig = Figure()
for i in 1:5
  ax = WGLMakie.Axis(fig[i,1])
  density!(ax, rand(1_000))
end
for ax in fig.content
  linkaxes!(fig.content[1], ax)
end
fig
```

### Additional contract requirements

Axes linked transitively through repeated `linkaxes!` calls must stay synchronized: changing either dimension's limits on any axis in the linked group must update the corresponding limits on every other axis in that group.
