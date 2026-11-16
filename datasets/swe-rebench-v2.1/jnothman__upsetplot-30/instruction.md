Support transposed plot
Really, according to the original UpSet work, the current display is transposed. We should support the original format of having the intersection size bars horizontal.

### Additional contract requirements

`UpSet.__init__` in `upsetplot.plotting` accepts an `orientation` keyword argument supports `'horizontal'` (the default) and `'vertical'`. The `plot` function accepts the same `orientation` keyword argument. With `orientation='horizontal'`, the intersection-size bars are vertical and are arranged left to right; with `orientation='vertical'`, the intersection-size bars are horizontal and are arranged bottom to top. `UpSet(data, orientation='horizontal').make_grid(fig)` produces a figure whose height is less than its width, and the width-to-height ratio for `orientation='vertical'` is lower than for `orientation='horizontal'`.
