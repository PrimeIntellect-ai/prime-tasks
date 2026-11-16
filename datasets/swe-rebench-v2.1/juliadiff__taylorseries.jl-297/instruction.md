Accuracy issues compared to RK-family solvers from OrdinaryDiffEq.jl?
I am trying to solve a nonlinear gasdynamics ODE system with high accuracy.  The ODE system does have a `0/0` pole it approaches, and the goal is to be able to use `TaylorIntegration.jl` to approach that pole accurately and robustly.  However, I began by checking the `TaylorIntegration.jl` solution against `Vern7` from `OrdinaryDiffEq.jl` with `abstol=1e-12, reltol=0.0`.  The `Vern7` solver produces good results on the ODE system (as verified through `BigFloat` solutions), so I began by comparing a `Vern7` and `TaylorMethod` solution away from the pole.  However, even with similar or tighter tolerances on the `TaylorMethod` solution, the Euclidean distance between solution points grows to `Order(1e-3)`, so ~9 orders of magnitude higher than the integration tolerance.

I also verified that I am able to get very comparable high-accuracy results between `TaylorIntegration.jl` and `OrdinaryDiffEq.jl` `Vern7` solutions for a nonlinear test ODE system where no subtractive cancellation takes place in the denominators, so I don't believe this to be user error (but I could be wrong/missing something!).

Attached is a `Pluto.jl` notebook, but I will also paste code below.  Note that I tried different values of the method order, and leaving on vs. omitting `parse_eqs` and they didn't seem to ultimately change the magnitude of solution differences.  Again, the `tspan` right-side endpoint prescribed below is still some distance away from the singularity, and the plot shows significant differences building up quite early in the solution trajectory.

```Julia
using OrdinaryDiffEq
using TaylorIntegration
using LinearAlgebra
using Plots

function TMM_odesys!(primes, dependent, params, independent)
    γ = params[1]
    θ = independent
    Mr = dependent[1]
    Mθ = dependent[2]
    gm1o2 = (γ - 1) / 2
    Mθsq = Mθ * Mθ
    Mθsqm1 = Mθsq - 1
    Mθcotθ = Mθ * cot(θ)
    # slightly excessive paretheses, but equations are correct
    primes[1] = ((Mθ * ((gm1o2 * ((Mr * Mr) + (Mr * Mθcotθ))) + Mθsq - 1)) / Mθsqm1)
    primes[2] = (((((gm1o2 * Mθsq) + 1) * (Mr + Mθcotθ)) - (Mr * Mθsqm1)) / Mθsqm1)
    return nothing
end

# Simple Euclidean distance between two points
function solptdiff(u0, u1)
  diff = u0 - u1
  sqrt(dot(diff, diff))
end

cf_test_prob = ODEProblem(TMM_odesys!, [2.5, 0.0], (deg2rad(0.1), 0.4), [1.4])

Vern7sol = solve(cf_test_prob, Vern7(), abstol = 1e-12, reltol = 0.0)

TIsol = solve(cf_test_prob, TaylorMethod(30), abstol = 1e-13, parse_eqs = false)

solptdiff(Vern7sol.u[end], TIsol.u[end]) # On my system, this returns 0.004776986921762344 , much higher than expected

# Next use taylorinteg() to match time points with the Vern7 solution so differences can be compared step-by-step
matching_t_sol = taylorinteg(TMM_odesys!, [2.5, 0.0], Vern7sol.t, 30, 1e-13, [1.4], parse_eqs = false)

# Convenience function to change the returned matrix to a vector of vectors so the difference function can be simply broadcast
function mat2vecvec(m)
  nr = size(m, 1)
  v = Vector{Vector{typeof(m[1,1])}}(undef, nr)
  for i = 1:nr
    v[i] = m[i, :]
  end
  return v
end

matching_t_sol_vv = mat2vecvec(matching_t_sol);

diffs = solptdiff.(Vern7sol.u, matching_t_sol_vv);

# Omit the first point since they are both the IC and the difference is a zero vector which doesn't work with the semilog plotting
plot(Vern7sol.t[2:end], diffs[2:end], yscale = :log10, legend_position = false)
```

[taylorinteg_cf_test.jl.txt](https://github.com/PerezHz/TaylorIntegration.jl/files/7742117/taylorinteg_cf_test.jl.txt)

### Additional contract requirements

- `tan(x::Taylor1)` and `tan(x::TaylorN)` return the Taylor expansion of the tangent of `x`, agreeing with `sin(x)/cos(x)`, with the same order and coefficient type as `x`.
- `cot(x::Taylor1)` and `cot(x::TaylorN)` return the Taylor expansion of the cotangent of `x`, equal to `1/tan(x)`.
- For `tan`, a constant term located at a pole of the tangent (for example `π/2`) is reflected in the resulting coefficients; no explicit error is raised.
