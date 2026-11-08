Constraining Symmetric matrix to be equal to a Hermitian matrix is not Hermitian
Bug introduced in #3797: before if I tried to constrain A == B for Symmetric A and Hermitian B it would give me an error. Now it silently fails.

```julia

using JuMP
using LinearAlgebra
import Hypatia
import Ket
import Random

function dual_test(d)
    Random.seed!(1)
    ρ = Ket.random_state(Float64, d^2, 1)

    model = Model()
    @variable(model, σ[1:d^2, 1:d^2] in PSDCone())
    @variable(model, λ)
    noisy_state = Hermitian(ρ + λ * I(d^2))
    @constraint(model, witness_constraint, σ == noisy_state)
    @objective(model, Min, λ)
    @constraint(model, Ket.partial_transpose(σ, 2, [d, d]) in PSDCone())

    set_optimizer(model, Hypatia.Optimizer)
    optimize!(model)

    W = dual(witness_constraint)
    return W
end
```

### Additional contract requirements

- For a constraint equating a symmetric matrix to a Hermitian matrix, the constraint’s dual value must itself be Hermitian.
