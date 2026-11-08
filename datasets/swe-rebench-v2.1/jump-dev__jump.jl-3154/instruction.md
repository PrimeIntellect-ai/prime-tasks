Direct input of PSD constraints
Although a variable can be declared to belong in the PSD cone (e.g., `foo = @variable(problem, [1:dim, 1:dim] in COI.HermitianPSDCone())`), I have not yet found a way to directly input PSD *constraints*.

For example, I frequently would like to impose things of the sort `@constraint(problem, operation(foo) in COI.HermitianPSDCone())`, where `operation` is any transformation on the variable.

My current workaround is to introduce a new variable in the PSD cone and enforce equality constraints, for instance:

```
"""
Enforce PSD constraint on the input matrix.
Uses dummy vars. to enforce PSD (not possible directly in ComplexOptInterface?).
"""
function ispsd(problem::Model, A::AbstractMatrix)
    @assert size(A,1) == size(A,2) "Matrix must be square."
    @assert length(size(A)) == 2 "Matrix must be bidimensional."

    dim = size(A, 1)
    PSD = @variable(problem, [1:dim, 1:dim] in ComplexOptInterface.HermitianPSDCone())
    @constraint(problem, A .== PSD)
end
```

then call `ispsd(problem, operation(foo))`.

Is there a more economic way to do this? Or maybe does ComplexOptInterface already support PSD constraints directly?

### Additional contract requirements

The Hermitian PSD constraint must preserve the complete supplied matrix expression, including its off-diagonal terms.
