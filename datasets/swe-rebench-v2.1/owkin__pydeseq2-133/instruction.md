[BUG]` beta` referenced before assignment
**Describe the bug**
```
lib/python3.10/site-packages/pydeseq2/utils.py", line 471, in irls_solver
    mu = np.maximum(size_factors * np.exp(X @ beta), min_mu)
UnboundLocalError: local variable 'beta' referenced before assignment
```



![image](https://github.com/owkin/PyDESeq2/assets/39041821/c758f0ef-df80-4515-bfbd-b273f38b4fb6)

### Additional contract requirements

- `pydeseq2.utils.irls_solver(counts, size_factors, design_matrix, disp, ...)` must
  not raise `UnboundLocalError` when `design_matrix` does not have full column rank.
  It must return the fitted coefficients instead of failing with an unbound local
  variable.
- `irls_solver` returns a tuple `(beta, mu, H, converged)`, where `beta` is a finite
  array with one entry per column of `design_matrix`.
