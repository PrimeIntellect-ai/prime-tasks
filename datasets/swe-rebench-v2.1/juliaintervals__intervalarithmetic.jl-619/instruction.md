[HIDDEN]
In current master:
```julia
julia> using IntervalArithmetic

julia> a = interval(1,2)
[1.0, 2.0]_com

julia> a^4
[1.0, 16.0]_com_NG
```
The *non-guaranteed* flag is disturbing. The problem arises from [these lines](https://github.com/JuliaIntervals/IntervalArithmetic.jl/blob/946493a03a1c4535334956302ec7a2c9807e0d59/src/intervals/arithmetic/power.jl#L63C1-L66C74), which use `convert`. This, incidentally, does not respects the `PowerMode` in use.

### Additional contract requirements

- Literal integer powers of intervals must respect the `PowerMode` currently in use and must not have a spurious non-guaranteed status when the result is guaranteed.
- In the reported example, `a^4` must have bounds `[1, 16]` and be guaranteed.
