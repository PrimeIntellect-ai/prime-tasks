Affine constraint between two DBC constraints should work
```
grid = generate_grid(Quadrilateral, (1,1))
dh = DofHandler(grid)
push!(dh, :u, 1)
close!(dh)

ch_affine_first = ConstraintHandler(dh)
add!(ch_affine_first, AffineConstraint(2, [3 => 1.0], 0.0))
add!(ch_affine_first, Dirichlet(:u, getfaceset(grid, "right"), (x, t) -> 1)) # Works without this inhomogeneity
close!(ch_affine_first)
update!(ch_affine_first, 0)

ch_dbc_first = ConstraintHandler(dh)
add!(ch_dbc_first, Dirichlet(:u, getfaceset(grid, "right"), (x, t) -> 1)) # Works without this inhomogeneity
add!(ch_dbc_first, AffineConstraint(2, [3 => 1.0], 0.0))
close!(ch_dbc_first)
update!(ch_dbc_first, 0)

K_affine_first = create_sparsity_pattern(dh, ch_affine_first)
f_affine_first = zeros(size(K_affine_first, 1))
fill!(K_affine_first.nzval, 1)

K_dbc_first = create_sparsity_pattern(dh, ch_dbc_first)
f_dbc_first = zeros(size(K_dbc_first, 1))
fill!(K_dbc_first.nzval, 1)

apply!(K_affine_first, f_affine_first, ch_affine_first)
apply!(K_dbc_first, f_dbc_first, ch_dbc_first)
```

`K_affine_first` and `K_dbc_first` are equal, but not `f_affine_first` and `f_dbc_first`.

### Additional contract requirements

- When an affine constraint depends on a degree of freedom constrained by another affine constraint, `close!(ch)` must throw `ErrorException("nested affine constraints currently not supported")`.
