collapse (document) does not work correctly
As document https://juliastats.org/TimeSeries.jl/latest/combine/#collapse-1
Considering following code
```julia
dates = [Date(2018, 1, 1), Date(2018, 1, 2), Date(2019, 1, 1), Date(2019, 2, 1)]
ta = TimeArray(dates, rand(length(dates)))
collapse(ta, month, last)

```

gives only 2 entries
```
│            │ A      │
├────────────┼────────┤
│ 2019-01-01 │ 0.405  │
│ 2019-02-01 │ 0.9778 │
```
while I expects 3 entries
```
│            │ A      │
├────────────┼────────┤
│ 2018-01-02 │ 0.9279 │
│ 2019-01-01 │ 0.405  │
│ 2019-02-01 │ 0.9778 │
```
and I have to write `collapse(ta, x->floor(x, Month(1)), last)`.
shall we change the api to `collapse(ta, Month(1), last)` to reduce confusion, just like what https://github.com/femtotrader/TimeSeriesResampler.jl do?
