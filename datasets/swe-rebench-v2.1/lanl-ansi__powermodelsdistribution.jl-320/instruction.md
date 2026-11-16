BUG: start_value of single-phase component can't be assigned (v0.10.0)
Hello,
I was playing with the new version a bit, and I reduced a three-phase bus into a single-phase bus to see what happens. The reduction is as follows:
```julia
using PowerModelsDistributions, Ipopt

ipopt_solver = optimizer_with_attributes(Ipopt.Optimizer, "print_level"=>0)

data = parse_file("/test/data/opendss/case3_unbalanced.dss"; data_model = MATHEMATICAL)
delete!(data["load"], "2")
delete!(data["load"], "3")
data["bus"]["3"]["terminals"] = [2]
data["bus"]["3"]["grounded"] = Bool[0.0]
data["branch"]["1"]["t_connections"] = [2]
data["branch"]["1"]["f_connections"] = [2]
run_ac_mc_pf(data, ipopt_solver)
```
So far, so good. But if I try to assign a start value to the newly reduced single-phase bus, I get an error:
```julia
data["bus"]["3"]["vm_start"] = [0.9959]  # 0.9959 instead of [0.9959] also won't work
run_ac_mc_pf(data, ipopt_solver) #this errors
```
The last line returns "ERROR: BoundsError: attempt to access 1-element Array{Float64,1} at index [2]".
This is because of how 't' is defined in [src/core/variable.jl#L34](https://github.com/lanl-ansi/PowerModelsDistribution.jl/blob/master/src/core/variable.jl#L34), which works fine as long as the buses terminals are [1, 2, 3], as is the case in all tests. This is also the case for generators variables and the other variables in general.
Imho this is a bug, because you might want to have single-terminal buses and definitely single-phase generators.
I am happy to help, but I'd first like to hear your opinion one how to nicely fix this.
In other similar instances, e.g., assigning lower/upper bounds, enumerate() is resorted to, but I am not sure it would be very elegant in this context.

### Additional contract requirements

Start values supplied for component variables must be assigned to their corresponding active conductor or connection, including bus terminals, generator connections, and branch connections.
