NanTestTrans fails if applied to a 'null' loop
We get an error saying that the loop variable is `None`. Without looking at the code, I think this case should probably be supported so I'm marking this as a bug.

### Additional contract requirements

- For the invoke schedule at index 0 in `25.1_kern_two_domain.f90` using the `dynamo0.3` API, `str(VariablesAccessInfo(invoke.schedule))` must be exactly `a: READ, b: READ, f1: READWRITE, f2: READWRITE, map_w3: READ, ncell_2d_no_halos: READ, ndf_w3: READ, nlayers: READ, undf_w3: READ`.
