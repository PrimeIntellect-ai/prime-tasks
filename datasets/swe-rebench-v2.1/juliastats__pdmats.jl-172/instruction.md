Unifying constructor? e.g. PDMat(Diagonal(...)) = PDiagMat(diag(...))
Would be really helpful in downstream code if I wouldn't have to think whether I've got a `Diagonal` -> wrap in `PDiagMat` or not -> wrap in `PDMat`. How about
```julia
[HIDDEN]
```
for example?

### Additional contract requirements

The unified positive-definite matrix constructor `AbstractPDMat` must accept a `Diagonal` matrix and produce a `PDiagMat` representing the same diagonal matrix.
