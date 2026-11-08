callback_value doesn't work if nonlinear constraint present
If nonlinear constraint is present callback_value returns initial condition for decision variable always.
Not sure is it about Ipopt.jl or JuMP or MathOptInterface... or something else

Here code sample to reproduce
```
using JuMP, Ipopt

model = Model(Ipopt.Optimizer)
set_silent(model)

@variable(model, 0 <= x <= 1, start = 0.1)
@objective(model, Min, x^2)

# @NLconstraint(model, x^3 >= 0)

function callback(args...)
    println(callback_value(model, x))
    return true
end

MOI.set(model, Ipopt.CallbackFunction(), callback)

optimize!(model)
```

It prints decision variable value at each step

But if you uncomment NLconstraint it will print always only initial value.  But problem still get solved though.
