`hessian_sparsity` fails with registered funcitons
Due to unknown linearity
```julia
ERROR: Failed to apply rule (~f)(~(x::isidx)) => if haslinearity_1(~f)
        #= /home/fredrikb/.julia/packages/Symbolics/J8IHJ/src/diff.jl:586 =#
        combine_terms_1(linearity_1(~f), ~x)
    else
        #= /home/fredrikb/.julia/packages/Symbolics/J8IHJ/src/diff.jl:588 =#
        error("Function of unknown linearity used: ", ~f)
    end on expression Base.FastMath.exp_fast(Symbolics.TermCombination(Set([Dict(139 => 1), Dict(139 => 2)])))
```
How would one go about registering the derivative for a function as well?

### Additional contract requirements

- For `hessian_sparsity`, registering a symbolic derivative is not the way to describe a registered function’s effect on sparsity. Users must be able to declare its linearity with respect to each argument, and sparsity analysis must honor those declarations: a declared linear dependence does not introduce curvature from that function, while a nonlinear dependence may.
