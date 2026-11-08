Rename autode.opt.coordinates.primitive.Distance and use values for optimisers
1. There is a clash between `autode.opt.coordinates.primitives.Distance` and `autode.values.Distance`. Maybe the first one could be renamed to BondDistance?
2. Use `autode.value.Distance` for trust radius in the optimisers.

### Additional contract requirements

- The optimisers expose their trust radius (maximum step size) as the public attribute `alpha`, which must be an `autode.values.Distance` value (unit-aware), not a plain `float`. This applies to `RFOptimiser`, `CRFOptimiser`, `PRFOptimiser` and `HybridTRMOptimiser`; constructing any of them with a plain float `init_alpha`/`init_trust` still yields a `Distance` `alpha`.
