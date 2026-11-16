Redefine the onsiteselectors and hoppingselectors of a TightbindingModel
I wonder whether the capability to redefine the onsiteselectors and hoppingselectors of a given `Tightbindingmodel` made out of several hopping and onsite terms could be useful or not.
I was thinking about a new function:
``modifierfunc!(model, region = ...)``
where `model = onsite_1 + ... + onsite_N+ hopping_1 + ... +hopping_M` and onsite_x (hopping_x) are arbitrary onsite(hopping) terms.
This new functionality would enable us to initially write region-independent TBmodels. This may reduce the code complexity when building: a complex heterostructure or different  heterostructures out of the same model, since the model is created only once.
For instance, if we want to build the hamiltonians corresponding to two SNS junctions (1 and 2) with different geometries using the same model for the normal(N) and superconducting (S) regions, we could simply do:

```
hamSNS1 = hamiltonian(lat1, modifierfunc!(modelN,region=(r,dr)->regionN1) + modifierfunc!(modelS,regionS1))
hamSNS2 = hamiltonian(lat2, modifierfunc!(modelN,region=(r,dr)->regionN2) + modifierfunc!(modelS,regionS2))
```

### Additional contract requirements

The public operations for redefining selectors on a `TightbindingModel` are
`onsiteselector!(model::TightbindingModel; region = missing, sublats = missing)` and
`hoppingselector!(model::TightbindingModel; region = missing, sublats = missing, dn = missing, range = missing)`.
They replace the selectors on the corresponding onsite or hopping terms, respectively, while preserving the terms' other content and leaving terms of the other kind unaffected. This allows one set of terms to be specialized for different geometries and used to construct the corresponding Hamiltonians.
