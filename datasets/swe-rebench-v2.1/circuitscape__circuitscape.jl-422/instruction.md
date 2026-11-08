type GraphProblem has no field cum_node_curr when parallelize=True
Hi,

I'm using Circuitscape 5.13.1 on a remote server. Tests were OK, and I could run Circuitscape with my data in pairwise mode. However, I encounter the following problem when trying to use parallelize option (even though the run seem to be complete, all output files present in output directory and similar to the run without parallelization):  ```type GraphProblem has no field cum_node_curr```.

```julia
(...)
[ Info: 2023-10-13 16:22:59 : Time taken to construct preconditioner = 1.4387e-5 seconds
[ Info: 2023-10-13 16:22:59 : Time taken to construct local nodemap = 3.215e-6 seconds
[ Info: 2023-10-13 16:22:59 : Time taken to construct preconditioner = 7.0988e-5 seconds
[ Info: 2023-10-13 16:22:59 : Time taken to construct local nodemap = 3.0e-6 seconds
      From worker 4:	[ Info: 2023-10-13 16:22:59 : Scheduling pair 53 of 54 to be solved
      From worker 4:	[ Info: 2023-10-13 16:22:59 : Solving pair 53 of 54
      From worker 4:	[ Info: 2023-10-13 16:22:59 : Time taken to solve linear system = 1.8561e-5 seconds
      From worker 4:	[ Info: 2023-10-13 16:22:59 : Time taken to write voltage maps = 0.044609064 seconds
      From worker 4:	[ Info: 2023-10-13 16:22:59 : Time taken to calculate current maps = 0.066434379 seconds
[ Info: 2023-10-13 16:22:59 : Time taken to construct preconditioner = 7.3132e-5 seconds
[ Info: 2023-10-13 16:22:59 : Time taken to construct local nodemap = 3.215e-6 seconds
      From worker 3:	[ Info: 2023-10-13 16:22:59 : Scheduling pair 54 of 54 to be solved
      From worker 3:	[ Info: 2023-10-13 16:22:59 : Solving pair 54 of 54
      From worker 3:	[ Info: 2023-10-13 16:22:59 : Time taken to solve linear system = 2.5975e-5 seconds
      From worker 3:	[ Info: 2023-10-13 16:23:00 : Time taken to write voltage maps = 0.384036873 seconds
      From worker 3:	[ Info: 2023-10-13 16:23:00 : Time taken to calculate current maps = 0.688962306 seconds
ERROR: type GraphProblem has no field cum_node_curr
Stacktrace:
 [1] getproperty
   @ ./Base.jl:37 [inlined]
 [2] network_pairwise(T::Type, V::Type, cfg::Dict{String, String})
   @ Circuitscape ~/mambaforge/envs/claire/share/julia/packages/Circuitscape/XcB67/src/network/pairwise.jl:23
 [3] _compute(T::Type, V::Type, cfg::Dict{String, String})
   @ Circuitscape ~/mambaforge/envs/claire/share/julia/packages/Circuitscape/XcB67/src/run.jl:53
 [4] macro expansion
   @ ./timing.jl:393 [inlined]
 [5] compute(path::String)
   @ Circuitscape ~/mambaforge/envs/claire/share/julia/packages/Circuitscape/XcB67/src/run.jl:31
 [6] top-level scope
   @ REPL[3]:1

```

Problem occurs when I add the lines (whether max_parallel is specified or not):
```
parallelize = True
```
to the INI file. INI file, edge list and node list attached.
[test.ini.txt](https://github.com/Circuitscape/Circuitscape.jl/files/12894580/test_small.ini.txt)
[test_nodes.txt](https://github.com/Circuitscape/Circuitscape.jl/files/12894581/test_small_nodes.txt)
[test_weighted_edges.txt](https://github.com/Circuitscape/Circuitscape.jl/files/12894582/test_small_weighted_edges.txt)


**Circuitscape and Julia version**
Circuitscape v5.13.1
Julia v1.9.3
Ubuntu 22.04.3 LTS
