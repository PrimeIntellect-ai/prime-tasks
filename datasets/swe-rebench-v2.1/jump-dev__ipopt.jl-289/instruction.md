Intermediate callback with MOI: primal values are constant along the iterations
The following MWE breaks on Ipopt.jl#master (same example as [here](https://github.com/jump-dev/Ipopt.jl/blob/master/test/MOI_wrapper.jl#L225-L257), but with a different starting point):
```julia
using Test
using Ipopt
using MathOptInterface
const MOI = MathOptInterface

function test_callback()
    model = Ipopt.Optimizer()
    MOI.set(model, MOI.RawParameter("print_level"), 0)
    x = MOI.add_variable(model)
    MOI.add_constraint(model, MOI.SingleVariable(x), MOI.GreaterThan(1.0))
    MOI.set(model, MOI.VariablePrimalStart(), x, 2.0)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    f = MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, x)], 0.5)
    MOI.set(model, MOI.ObjectiveFunction{typeof(f)}(), f)
    x_vals = Float64[]
    function my_callback(
        prob::IpoptProblem,
        alg_mod::Cint,
        iter_count::Cint,
        obj_value::Float64,
        inf_pr::Float64,
        inf_du::Float64,
        mu::Float64,
        d_norm::Float64,
        regularization_size::Float64,
        alpha_du::Float64,
        alpha_pr::Float64,
        ls_trials::Cint,
    )
        c = Ipopt.column(x)
        push!(x_vals, prob.x[c])
        @test isapprox(obj_value, 1.0 * x_vals[end] + 0.5, atol = 1e-1)
        return iter_count < 1
    end
    MOI.set(model, Ipopt.CallbackFunction(), my_callback)
    MOI.optimize!(model)
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.INTERRUPTED
    @test length(x_vals) == 2
end

test_callback()
```

The problem is that inside Ipopt.jl, the array `prob.x` is not updated along the iterations( Ipopt updates the values in `prob.x` only once the iterations are over). Hence, inside `my_callback`, `prob.x` is constant and set to the initial value passed to Ipopt.

To avoid this, I see two solutions forward:
[HIDDEN]

### Additional contract requirements

During an intermediate callback, a query for a variable's primal value must reflect Ipopt's current iterate, rather than a stale initial value. The reported objective value and queried primal values must describe the same iterate.
