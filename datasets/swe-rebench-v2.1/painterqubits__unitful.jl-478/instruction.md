incorrect preferred units conversion with atomic units
```Julia
using Unitful

using Unitful: preferunits
using UnitfulAtomic: me_au, e_au

preferunits(u"cm", u"ns", me_au, e_au / u"ns")

@show dimension(upreferred(u"V/cm"))
@show dimension(u"V/cm")

@assert dimension(upreferred(u"V/cm")) == dimension(u"V/cm")

```

results in

```Julia
dimension(upreferred(u"V/cm")) = 𝐋 𝐌 𝐈⁻¹ 𝐓⁻⁴
dimension(u"V/cm") = 𝐋 𝐌 𝐈⁻¹ 𝐓⁻³
ERROR: LoadError: AssertionError: dimension(upreferred(u"V/cm")) == dimension(u"V/cm")
[...]
```

with

```
[1986cc42] Unitful v1.8.0
[a7773ee8] UnitfulAtomic v1.0.0
```
