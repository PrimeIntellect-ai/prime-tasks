Compilation time in the `warm_up` method
After adding the `warm_up` method from #602 in a solver, it seems that the compilation time is accounted in the results.
<img width="515" alt="image" src="https://github.com/benchopt/benchopt/assets/77896657/494c33bb-fe84-4e38-b378-0944945882e1">

### Additional contract requirements

- If a solver defines a `warm_up` method, the framework calls it exactly once per
  solver instance, before the first benchmark run.
- The duration of `warm_up` (for example, a one-time compilation) must not be
  accounted for in the benchmark results: the per-run `time` values reported by the
  benchmark measure only the solver's `run` call, not the preceding `warm_up`.
