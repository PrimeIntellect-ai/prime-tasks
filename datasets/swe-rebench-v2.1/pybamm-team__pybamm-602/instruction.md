consistency between entering domains as lists or not
sometimes domains need to be entered as a list and sometimes they don't. make this consistent across classes.
potentially relax check on the variable `r` so that it's domain can be anyting (but keep check on `r_n` should be neg particle and same for `r_p`

### Additional contract requirements

- The spatial variable is created with `pybamm.SpatialVariable(name, domain)`, where `domain` may be given either as a single domain name string or as a list of domain names.
- `r_n` must be created with the domain `["negative particle"]` and `r_p` with `["positive particle"]`; any other domain for these names is rejected with `pybamm.DomainError`.
- `r` must be created with a particle domain; any other domain is rejected with `pybamm.DomainError`.
- A name that is not a known spatial variable, or a missing or empty domain, raises `ValueError`.
