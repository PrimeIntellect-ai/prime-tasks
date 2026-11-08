Display Interval{Float32} differently
e.g. `[1f0, 2f0]`

### Additional contract requirements

- Add a public function `basic_representation(a::Interval{Float32}, format=nothing) -> String` in module `IntervalArithmetic` that returns the textual representation of the interval.
- With `format = :standard`, the result is `[lo f0, hi f0]`.
- With `format = :full`, the result is `Interval(lo f0, hi f0)`.
- With `format = :midpoint`, the result is `mid f0 ± rad f0`.
- When `format` is `nothing`, the global display format is used.
- An empty `Interval{Float32}` is represented as `∅`.
- Infinite bounds are represented using `∞`, retaining the sign of negative infinity.
- `setformat(fmt::Symbol)` sets the global display format used when `basic_representation` is called with `format = nothing`.


- For `format = :full`, integral Float32 bounds include a decimal point and one trailing zero; for example, the results for `Interval{Float32}(1, 2)` and `Interval{Float32}(-1, Inf)` are `Interval(1.0f0, 2.0f0)` and `Interval(-1.0f0, ∞)`, respectively.
