Incorrect dual variable extracted from equality constraint between Hermitian matrices
When I use a constraint of the form `@constraint(model, A == B)`, where `A` and `B` are Hermitian matrices, for some reason the dual variable associated to this constraint has the off-diagonal elements multiplied by 2. I've tested a couple of different solvers, so the bug must be inside JuMP itself. A MWE follows below. Note the text-to-last line, where I'm dividing the off-diagonal elements of the dual variable by 2 to make it match the primal result.

```julia

using JuMP
using LinearAlgebra
import Hypatia
import Clarabel
import Ket
import Random

function dual_test(d)
    Random.seed!(1)
    ρ = Ket.random_state(d^2, 1)

    model = Model()
    @variable(model, σ[1:d^2, 1:d^2] in HermitianPSDCone())
    @variable(model, λ)
    noisy_state = Hermitian(ρ + λ * I(d^2))
    @constraint(model, witness_constraint, σ == noisy_state)
    @objective(model, Min, λ)
    @constraint(model, Ket.partial_transpose(σ, 2, [d, d]) in HermitianPSDCone())

    set_optimizer(model, Hypatia.Optimizer)
    #set_optimizer(model, Clarabel.Optimizer)
    optimize!(model)

    W = dual(witness_constraint)
    W = Hermitian(Diagonal(W) + 0.5(W - Diagonal(W))) #workaround
    return objective_value(model), dot(ρ, W)
end
```
