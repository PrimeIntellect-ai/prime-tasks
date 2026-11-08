`gcd` for vectors of elements
Similarly to the implementations in `Base` for vectors, e.g. `gcd(abc::AbstractArray{<:Integer}) in Base at intfuncs.jl:135`, I would like the euclidean Ring interface to be extended by a method `gcd(::AbstractArray{<:T}) where T <: RingElem` [HIDDEN].

This is not a large effort for this package but allows for some convenience and readability in downstream code.

If my request gets approved, I can do the needed changes to the interface.
