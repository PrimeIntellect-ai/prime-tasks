Add a `coeffs` method for `fq_nmod`
For somewhat efficient conversion between `fq_nmod` and GAP finite fields of larger degree, it would be useful to have a method `coeffs` for `fq_nmod` which returns a `Vector{UInt}` with all coefficient in one go, instead of having to get each coefficient on its own (which is substantially slower).

Going the other way around, of course a constructor for `fq_nmod` taking such a vector would also be useful.

In the end, I mostly care about matrices, though; I guess there an in-place way to set the coefficients of an entry of a  `fq_nmod_mat` would be useful (say by having a `setindex!(a::fq_nmod_mat, u::Vector{UInt}, i::Int, j::Int)` method -- though of course it could also have a different, more internal sounding name like `_setindex!`.

[HIDDEN]

### Additional contract requirements

The method requested above for returning all coefficients of an `fq_nmod` element in
one go is exposed under the public name `coeffs_raw`. Its signature is
`coeffs_raw(x::fq_nmod)`; it returns a fresh `Vector{UInt}` of length
`degree(parent(x))`, containing the raw coefficients of `x`, with trailing zeros for
unused high-degree positions.

The reverse conversion is provided by the constructor
`fq_nmod(a::FqNmodFiniteField, b::Vector{UInt})`, which returns an element of `a`
whose coefficient vector has length `degree(a)` and is populated from `b`.

The in-place coefficient setter is `setindex_raw!(x::fq_nmod, c::UInt, i::Int)`,
which writes the raw value `c` at the zero-based index `i` of `x`, mutating `x` in
place, and returns `x` itself.

A matrix entry can be updated in place from a coefficient vector by constructing
an element of its field from that vector and assigning the element to the selected
matrix index. The resulting entry has the supplied coefficients, and other entries
are unchanged.
