PlotDataItem division by 0 when 'clipToView' option enabled
In pyqtgraph/graphicsItems/PlotDataItem.py, lines 683 thru 688:

```
dx = float(x[-1]-x[0]) / (len(x)-1)
# workaround for slowdown from numpy deprecation issues in 1.17 to 1.20+
# x0 = np.clip(int((range.left()-x[0])/dx) - 1*ds, 0, len(x)-1)
# x1 = np.clip(int((range.right()-x[0])/dx) + 2*ds, 0, len(x)-1)
x0 = fn.clip_scalar(int((range.left()-x[0])/dx) - 1*ds, 0, len(x)-1)
x1 = fn.clip_scalar(int((range.right()-x[0])/dx) + 2*ds, 0, len(x)-1)
```

[HIDDEN]

### Additional contract requirements

- When `clipToView` is enabled and all input X values are equal, `getData()` must return exactly one X and one Y value when the repeated X coordinate is outside the visible X range; when it is inside the visible X range, `getData()` must retain all input points.
- With `clipToView` enabled and zero X span, `getData()` must not raise a divide-by-zero exception.
