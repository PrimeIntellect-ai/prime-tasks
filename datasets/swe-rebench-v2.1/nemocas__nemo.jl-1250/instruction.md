Allow `FiniteField(fmpz(5),2)` and `GF(fmpz(5), 2)` and `GF(fmpz(5), 2, "t")`
These all work with `5` instead of `fmpz(5)`.

UPDATE: just to clarify, what I am looking for is "symmetry" here in what kind of calls are allowed, not necessarily that they return the "same" thing or even something of the same type. In that vein, these all work:
- `GF(5)`, `FiniteField(5)` -- produce a `Nemo.GaloisField`
- `GF(5,2)`, `FiniteField(5,2)` -- produce a `FqNmodFiniteField`
- `GF(fmpz(5))`, `FiniteField(fmpz(5))` -- produce a `Nemo.GaloisFmpzField`
- `FiniteField(fmpz(5), 2, "t")` -- produces a `FqFiniteField`

But these don't:
- `FiniteField(fmpz(5),2)` and `GF(fmpz(5), 2)` and `GF(fmpz(5), 2, "t")` -- all ought to produce the same field like `FiniteField(fmpz(5), 2, "t")`, so type `FqFiniteField`
