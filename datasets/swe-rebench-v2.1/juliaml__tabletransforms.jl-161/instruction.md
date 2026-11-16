OneHot should probably produce categorical arrays
Currently the resulting columns are just Vector{Bool}, maybe they should be categorical arrays.

### Additional contract requirements

OneHot-generated indicator columns must be categorical arrays by default when the transform is applied without an output-type option. No Boolean-vector opt-out is required.
