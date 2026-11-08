Add methods for `sind` and etc.
Currently it falls back to `sind(::Real)` defined in Base:

```julia
julia> sind(interval(0, 0))
ERROR: rem not defined for IntervalArithmetic.Interval{Float64}
```

### Additional contract requirements

Add public methods `sind`, `cosd`, and `sincosd` for interval arguments.

- `sind(x)` accepts an `Interval{T}` or a `BareInterval{T}` (where `T` is a numeric type such as `Float64`) and returns an interval of the same kind as the input containing the range of `sin(π·x/180)`. An empty input yields an empty interval.
- `cosd(x)` accepts an `Interval{T}` or a `BareInterval{T}` and returns an interval of the same kind as the input enclosing the range of `cos(π·x/180)`. An empty input yields an empty interval.
- `sincosd(x)` accepts an `Interval{T}` or a `BareInterval{T}` and returns a two-element tuple `(s, c)` whose elements are intervals of the same kind as the input, containing the sine and cosine of the degree-valued interval respectively. For an empty input both elements are empty intervals.


- For the following tested inputs, the results must be exactly as shown: `sind(interval(90, 270)) == interval(-1, 1)`, `sind(interval(180)) == interval(0)`, `sind(interval(360)) == interval(0)`, `sind(interval(90)) == interval(1)`, `sind(interval(270)) == interval(-1)`, `sind(bareinterval(90, 270)) == bareinterval(-1, 1)`, `sind(bareinterval(90)) == bareinterval(1)`, and `sind(bareinterval(270)) == bareinterval(-1)`; `cosd(interval(180, 360)) == interval(-1, 1)`, `cosd(interval(-45, 45)) == interval(1/sqrt(2), 1)`, `cosd(interval(180)) == interval(-1)`, `cosd(interval(360)) == interval(1)`, `cosd(interval(90)) == interval(0)`, `cosd(interval(270)) == interval(0)`, `cosd(bareinterval(180, 360)) == bareinterval(-1, 1)`, `cosd(bareinterval(180)) == bareinterval(-1)`, and `cosd(bareinterval(360)) == bareinterval(1)`; `sincosd(interval(180, 380))[2] == interval(-1, 1)`, `sincosd(interval(90, 270))[1] == interval(-1, 1)`, `sincosd(interval(-45, 45))[2] == interval(1/sqrt(2), 1)`, `sincosd(bareinterval(90, 270))[1] == bareinterval(-1, 1)`, and `sincosd(bareinterval(-45, 45))[2] == bareinterval(1/sqrt(2), 1)`.
