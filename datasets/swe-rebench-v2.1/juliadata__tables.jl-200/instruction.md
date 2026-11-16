adding Tables.table methods
@quinnj would you be OK to allow `AbstracVector{Symbol}` and `AbstractVector{<:AbstractString}` as a `header` in `Tables.table`.

relevant for a decision in https://github.com/JuliaData/DataFrames.jl/issues/2433#issuecomment-695050438.

### Additional contract requirements

- `Tables.table(m::AbstractMatrix; header)` accepts a `header` keyword that may be any iterable whose elements can be converted to `Symbol` (for example a `Vector{Symbol}`, an `AbstractVector{<:AbstractString}`, a view, a generator, or a range such as `1:3`). The elements are converted to `Symbol`s to form the column names.
- The resulting column names must have length equal to `size(m, 2)`; otherwise an `ArgumentError` is thrown.
- The column names are stored as a freshly allocated `Vector{Symbol}` that does not alias the supplied `header`, so mutating the supplied `header` afterwards does not change the table's column names.
