Position of constant in a sum constraint matters (sometimes)
This is a magic square model where the position of `s` in the `sum` constraints give an `INFEASIBLE solution` if the first constraint (the rows constraint) in the `for` loop is stated as
   `@constraint(model, sum(x[i,:]) == s) # INFEASIBLE`
but it works if it stated as
  `@constraint(model, s == sum(x[i,:]))  # This works`

What I have understood there shouldn't be any restriction on the position of the `sum` in a constraints (i.e. LHS or RHS).

For the second (column) constraint both ways work.
It's the same problem with the first diagonal constraint where position of `s` matters, while the second diagonal constraint works either way.

Note that `s` is a constant (Int64). If `s` has been defined as a variable then there is no problem.

Also, I tested with a simple model with a single `sum` constraint, but then there's no problem where the `sum` is placed (LHS or RHS).

```
using ConstraintSolver, JuMP
const CS = ConstraintSolver

function magic_square(n=4,print_solutions=true,all_solutions=true)

    model = Model(optimizer_with_attributes(CS.Optimizer,   "all_solutions"=> all_solutions,
                                                            "logging"=>[],
                                                            "traverse_strategy"=>:BFS,
                                                            "branch_split"=>:InHalf,
                                                            "time_limit"=>3,                                        ))
                                        ))

    s = round(Int,n*(n^2 + 1) / 2) # The total for each row, column, and the two main diaginals
    @variable(model, 1 <= x[1:n,1:n] <= n^2, Int)
    @constraint(model, x[:] in CS.AllDifferentSet())

    for i in 1:n
        # Rows
        # @constraint(model, s == sum(x[i,:]))  # This works
        @constraint(model, sum(x[i,:]) == s) # INFEASIBLE

        # Columns
        @constraint(model, sum(x[:,i]) == s) # This works
        # @constraint(model, s == sum(x[:,i])) # This works as well
    end

    # diagonals
    @constraint(model, s == sum([x[i,i] for i in 1:n])) # This works
    # @constraint(model, sum([x[i,i] for i in 1:n]) == s) # This yield INFEASIBLE solution

    @constraint(model, s == sum([x[i,n-i+1] for i in 1:n])) # This works
    # @constraint(model, sum([x[i,n-i+1] for i in 1:n]) == s) # This works as well

    optimize!(model)

    status = JuMP.termination_status(model)
    if status == MOI.OPTIMAL
        num_sols = MOI.get(model, MOI.ResultCount())
        println("num_sols:$num_sols\n")
        if print_solutions
            for sol in 1:num_sols
                println("solution #$sol")
                xx = convert.(Integer,JuMP.value.(x; result=sol))
                display(xx)
            end
        end
    else
        println("status:$status")
    end

    return status
end

print_solutions = true
all_solutions = false
@time magic_square(5,print_solutions,all_solutions)
```
