Error during change base ring
I have a polynomial over rationals and I am trying to change the base ring via `>change_base_ring(GaloisF, poly)` command. However, I get the following error:
```julia
>change_base_ring(GaloisF, poly)
ERROR: MethodError: no method matching (::Nemo.GaloisField)(::fmpq)
```
How can this be resolved?

### Additional contract requirements

A polynomial with rational coefficients must be convertible to a finite Galois field when each coefficient's denominator is invertible in that field. A rational with a denominator that is not invertible in the target field must be rejected rather than silently converted.
