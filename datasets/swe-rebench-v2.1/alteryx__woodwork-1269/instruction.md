Box plot dictionary has misleading values for high and low bounds in some cases.
As a Woodwork user, I want to be able to use the output of `series.ww.box_plot_dict` to build a box plot that makes sense.

Currently, Woodwork's use of IQR to determine the high and low outlier bounds can end up in situations where the high or low bound can be above or below the max or min values of the series. If a box plot is then built using these bounds, it's misleading, as it points to the range of the data being wider than it actually is.

An example using the following quantiles: `{0.0: 1 , 0.25: 42, 0.5: 145, 0.75: 284, 1.0: 977}` and our equation for calulating the bounds
```
IQR = q_3 - q_1
low_bound = q_1 - 1.5IQR
high_bound = q_3 + 1.5IQR
```
leaves us with a high bound of 647, which makes sense, but a low bound of -321, which is way below the min value of 1.

We should update our high and low bounds to be

```python
[HIDDEN]
```

### Additional contract requirements

- `box_plot_dict` accepts an optional `quantiles` mapping and an optional boolean `include_indices_and_values`.
- The low bound must not be below the series minimum, and the high bound must not exceed the series maximum.
- When `quantiles` is provided but does not contain all four of the keys `0.0`, `0.25`, `0.75`, and `1.0`, raise `ValueError` with the message: `Input quantiles do not contain the minimum necessary quantiles for box plot calculation: 0.0 (the minimum value), 0.25 (the first quartile), 0.75 (the third quartile), and 1.0 (the maximum value).`
- The returned dictionary contains at least the keys `low_bound`, `high_bound`, and `quantiles`. When `include_indices_and_values` is `True`, it also contains `low_values`, `high_values`, `low_indices`, and `high_indices`.
