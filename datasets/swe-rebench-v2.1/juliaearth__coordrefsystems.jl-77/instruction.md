Add `Cartesian` constructor with tuple of numbers
The current constructors only cover the unitful case or cases with splat.

### Additional contract requirements

- The tuple constructors accept an explicit `Datum` type parameter, e.g. `Cartesian{WGS84Latest}((x₁, x₂, ...))`, and the resulting coordinate retains that datum; when the parameter is omitted it defaults to `NoDatum`.
- The raw-number tuple constructor throws an `ArgumentError` when the tuple contains an element that is not a plain number (for example a length quantity).
- The length-quantity tuple constructor throws an `ArgumentError` when the tuple contains a non-length value.
- The returned coordinate uses the promoted floating-point numeric type, e.g. `Cartesian((1, 2))` stores `Float64` coordinates.
