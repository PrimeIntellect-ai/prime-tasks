Duck typing LGG09 options
eg.  accept `alg = LGG09(δ=1e-3, template=[e25, -e25])`, compare to

```julia
e25 = zeros(48); e25[25] = 1.0
alg = LGG09(δ=1e-3, template=CustomDirections([e25, -e25]))
sol = solve(problem, T=20.0, alg=alg);

@btime solve($problem, T=20.0, alg=$alg);
    78.247 ms (160564 allocations: 32.46 MiB)
