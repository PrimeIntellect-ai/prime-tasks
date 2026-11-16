Add function for run-time parsing
The `@u_str` macro is useful when units are known in advance. In some cases, however, units must be determined at runtime. This requires parsing strings as numeric and Unitful values, which is currently sort of ugly:

```julia
val, unit = split(rawValue, " "; limit=2)
return parse(Float64, val)*(@eval @u_str $unit) # ugly
```
I'd like to propose that Unitful include a function which exposes this kind of behavior (i.e. parse quantity from string). It would be good if it were resilient to having a space (or not) between the numeric and the unit.

### Additional contract requirements

- Add a public function `uparse(str; unit_context=Unitful)` in the `Unitful` module.
- `str` is a string containing a Julia expression that represents a unit, a tuple of units, or a quantity (a numeric value optionally followed by a unit expression).
- `unit_context` may be a `Module` or a `Vector{Module}`; identifiers appearing in `str` are resolved against the supplied module(s). It defaults to `Unitful`.
- `uparse` returns the value represented by the expression: a unit expression returns a `Unitful.Unit`, a quantity returns a `Unitful.Quantity`, a bare numeric expression returns its numeric value, and a tuple of unit expressions returns a tuple containing the corresponding units (for example, `m`, `m/s`, `1.0dB`, or `(m,s)`).
- `uparse` throws `Meta.ParseError` when `str` cannot be parsed as Julia code.
- `uparse` throws `ArgumentError` for syntactically valid Julia expressions that are not a unit, a tuple of units, or a quantity, including expressions containing disallowed symbols, unsupported function calls, or malformed unit tuples.
