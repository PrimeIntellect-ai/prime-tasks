[HIDDEN] setindex! function
```
F = GF(2, 3);
R, x = polynomial_ring(F, :x);
g = x^4 + x^3 + x^2 + 1;
coeffs = collect(coefficients(g))
G = zero_matrix(GF(2), 3, 7);
G[1, 1] = gen(F)
```
this should try to coerce and error

### Additional contract requirements

- When assigning a finite-field value to a matrix, the relevant `setindex!` operation must convert it to the matrix's coefficient ring and store the converted value when conversion succeeds.
- If coercion of an assigned value fails in `setindex!`, it must throw `ArgumentError`.
