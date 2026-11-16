Require finer control over `basefactor`
I'm working on a package [UnitfulGaussian.jl](https://github.com/abhro/UnitfulGaussian.jl) for handling CGS-ESU/CGS-EMU/Gaussian systems of units. I have the unit of charge franklin (or statcoulomb), but I'm having trouble using it in actual equations.

The definition of the charge unit is:

```julia
using Unitful
using Unitful: dyn, cm, @unit
#       symbol  abbrev.     name        equals          tf     autodocs
@unit   Fr      "Fr"        franklin    1sqrt(dyn)*cm   false
```

I'm trying to test this with 2 charges, both of `1Fr` charge, placed `1cm` apart from each other. By definition, the force should be `1dyn` (Coulomb's law). But it errors on conversion:
```julia-repl
julia> using Unitful: cm, dyn

julia> using UnitfulGaussian: Fr

julia> (1Fr)^2/(1cm)^2 |> dyn
ERROR: OverflowError: 1441151880758559 * 1441151880758559 overflowed for type Int64
Stacktrace:
      ⋮ internal @ Base.Checked, Base, Unitful, Core, Unknown
 [17] |>(x::Quantity{Float64, 𝐋 𝐌 𝐓^-2, Unitful.FreeUnits{(cm^-2, Fr^2), 𝐋 𝐌 𝐓^-2, nothing}}, f::Unitful.FreeUnits{(dyn,), 𝐋 𝐌 𝐓^-2, nothing})
    @ Base .\operators.jl:926
```

After some digging, I found that the problem was from `Unitful.basefactor`:
```julia-repl
julia> Unitful.basefactor(Fr)
(0.1, 1441151880758559//144115188075855872)
```
The second element in the tuple is a close approximation to `1//10`. I'm not sure how Unitful comes up with this number, but it's not allowing me to convert between units.
