`pvsystem.sapm` documentation: clarification of coefficients used
**Is your feature request related to a problem? Please describe.**
[`pvlib.pvsystem.sapm`](https://pvlib-python.readthedocs.io/en/stable/reference/generated/pvlib.pvsystem.sapm.html#pvlib.pvsystem.sapm) requires effective irradiance and SAPM coefficients as inputs.

https://github.com/pvlib/pvlib-python/blob/22364d85b2f0844624b9a8160ea38535b82d8360/pvlib/pvsystem.py#L2169-L2171
https://github.com/pvlib/pvlib-python/blob/22364d85b2f0844624b9a8160ea38535b82d8360/pvlib/pvsystem.py#L2176-L2178

`effective_irradiance` considers AOI/spectrum. The notes section explaining `module` contains a table explaining the SAPM coefficients:
https://github.com/pvlib/pvlib-python/blob/22364d85b2f0844624b9a8160ea38535b82d8360/pvlib/pvsystem.py#L2194-L2235

I'm wondering whether any clarification over which coefficients are actually used is necessary. I think it's helpful to present the full table, but could someone be misled into thinking that since `A0-A4` are required, a spectral correction is being applied (for example)

**Describe the solution you'd like**
Suggestion: add a line or two to the notes section clarifying which coefficients are used.

**Describe alternatives you've considered**
Such a revision could be redundant since `effective_irradiance` is already clearly (and correctly) defined. However, when I first glanced over these docs, I just felt like some clarification could help some users. Not a major issue; I am interested to hear whether anyone else thinks this would help or not.

### Additional contract requirements

- The Notes section of the `pvlib.pvsystem.sapm` documentation must state, before the coefficient table, which entries of `module` the model requires. Each of the following must be named there: `C0`, `C1`, `C2`, `C3`, `Isco`, `Impo`, `Voco`, `Vmpo`, `Aisc`, `Aimp`, `Bvoco`, `Mbvoc`, `Bvmpo`, `Mbvmp`, `N`, `Cells_in_Series`.
