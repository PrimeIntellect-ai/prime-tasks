GF(p,n) does not check if p is prime
When we ask for a finite field `GF(p)`, we check that `p` is prime and give a `DomainError` in the case where `p` is not prime.

But these checks seem to be skipped when we call `GF(p,n)`. For example
* `GF(4, 2)` gives a `ERROR: Problem in the Flint-Subsystem`, which is a less specific error than we would like.
* More troublesome, `GF(ZZ(4),2)` doesn't complain at all and somehow returns `Finite field of degree 2 over GF(4)`. But this isn't REALLY `GF(4)`, in fact we get an error if we look more closely:
```
julia> BadField = GF(ZZ(4), 2)
Finite field of degree 2 over GF(4)

julia> prime_field(BadField)
ERROR: DomainError with 4:
Characteristic must be prime
Stacktrace:
 [1] GF(n::ZZRingElem; cached::Bool)
   @ Nemo.Native ~/.julia/packages/Nemo/xM4S1/src/Native.jl:20
 [2] GF
   @ ~/.julia/packages/Nemo/xM4S1/src/Native.jl:18 [inlined]
 [3] #prime_field#420
   @ ~/.julia/packages/Hecke/ttSxw/src/Map/FiniteField.jl:10 [inlined]
 [4] prime_field(F::FqPolyRepField)
   @ Hecke ~/.julia/packages/Hecke/ttSxw/src/Map/FiniteField.jl:9
 [5] top-level scope
   @ REPL[28]:1
```
