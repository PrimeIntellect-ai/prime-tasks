inv fails for nmod_mat
```
julia> R = ResidueRing(ZZ,9)
julia> G = matrix(R,2,2,[2,1,1,2])
[2  1]
[1  2]
julia> inv(G)
Flint exception (Impossible inverse):
    Cannot invert modulo 2*0
ERROR: Problem in the Flint-Subsystem
Stacktrace:
 [1] error(::String) at ./error.jl:33
 [2] flint_abort() at .../.julia/packages/Nemo/mmz6V/src/Nemo.jl:118
 [3] inv(::nmod_mat) at .../.julia/packages/Nemo/mmz6V/src/flint/nmod_mat.jl:443
 [4] top-level scope at REPL[303]:1
```
It appears also for other residue rings
```
julia> R = ResidueRing(ZZ,9)
Integers modulo 9julia> G = matrix(R,2,2,[3,1,1,3])
[3  1]
[1  3]
julia> inv(G)
Flint exception (Impossible inverse):
    Cannot invert modulo 3*0
ERROR: Problem in the Flint-Subsystem

```
As far as I can tell the problem occurs when the entry at [1,1] is not invertible.
