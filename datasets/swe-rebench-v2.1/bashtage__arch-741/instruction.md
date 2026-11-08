Contiguous array error when calling arch_model
running an `arch_model` call as follows:

```
from arch import arch_model

...

g1 = arch_model(data, vol='GARCH',
                mean='Zero',
                p=1, q=1, dist='Normal')

model = g1.fit()

```

results in the following error (traceback at the end): `ValueError: ndarray is not C-contiguous` arising from a variable created within ` arch.univariate.volatility.py`

the `data` argument is simply a pandas Series of float64 values with a datetime index.

I can get around it by either:

- [HIDDEN] (based on advice here:
https://stackoverflow.com/a/26782930/2460063)

- or removing the `mean="Zero"` argument in the function call.


I'm working with numpy 2.0.1





Traceback:

```
---------------------------------------------------------------------------
ValueError                                Traceback (most recent call last)
Cell In[27], [line 1](vscode-notebook-cell:?execution_count=27&line=1)
----> [1](vscode-notebook-cell:?execution_count=27&line=1) model = g1.fit()

File ~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/base.py:667, in ARCHModel.fit(self, update_freq, disp, starting_values, cov_type, show_warning, first_obs, last_obs, tol, options, backcast)
    [665](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/base.py:665) sigma2 = np.zeros_like(resids)
    [666](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/base.py:666) self._backcast = backcast
--> [667](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/base.py:667) sv_volatility = v.starting_values(resids)
    [668](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/base.py:668) self._var_bounds = var_bounds = v.variance_bounds(resids)
    [669](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/base.py:669) v.compute_variance(sv_volatility, resids, sigma2, backcast, var_bounds)

File ~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:1208, in GARCH.starting_values(self, resids)
   [1205](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:1205) target *= scale ** (power / 2)
   [1207](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:1207) svs = []
-> [1208](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:1208) var_bounds = self.variance_bounds(resids)
   [1209](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:1209) backcast = self.backcast(resids)
   [1210](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:1210) llfs = np.zeros(len(abgs))

File ~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:1040, in GARCH.variance_bounds(self, resids, power)
   [1039](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:1039) def variance_bounds(self, resids: Float64Array, power: float = 2.0) -> Float64Array:
-> [1040](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:1040)     return super().variance_bounds(resids, self.power)

File ~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:536, in VolatilityProcess.variance_bounds(self, resids, power)
    [534](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:534) var_bound = np.zeros(nobs)
    [535](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:535) initial_value = w.dot(resids[:tau] ** 2.0)
--> [536](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:536) ewma_recursion(0.94, resids, var_bound, resids.shape[0], initial_value)
    [538](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:538) var_bounds = np.vstack((var_bound / 1e6, var_bound * 1e6)).T
    [539](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:539) var = resids.var()

File ~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:142, in ewma_recursion(lam, resids, sigma2, nobs, backcast)
    [136](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:136) # AA PATCH
    [137](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:137) [HIDDEN]
    [138](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:138)
    [139](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:139)
    [140](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:140) # Throw away bounds
    [141](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:141) var_bounds = np.ones((nobs, 2)) * np.array([-1.0, 1.7e308])
--> [142](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:142) rec.garch_recursion(
    [143](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:143)     np.array([0.0, 1.0 - lam, lam]),
    [144](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:144)     resids**2.0,
    [145](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:145)     resids,
    [146](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:146)     sigma2,
    [147](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:147)     1,
    [148](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:148)     0,
    [149](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:149)     1,
    [150](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:150)     nobs,
    [151](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:151)     backcast,
    [152](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:152)     var_bounds,
    [153](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:153) )
    [154](~/.virtualenvs/exercises/lib/python3.12/site-packages/arch/univariate/volatility.py:154) return sigma2

File arch/univariate/recursions.pyx:264, in arch.univariate.recursions.garch_recursion()

File <stringsource>:663, in View.MemoryView.memoryview_cwrapper()

File <stringsource>:353, in View.MemoryView.memoryview.__cinit__()

ValueError: ndarray is not C-contiguous
```

### Additional contract requirements

- Fitting an `arch_model` with `mean="Zero"` on a non-C-contiguous pandas Series of float64 observations with a datetime index must complete without raising `ValueError: ndarray is not C-contiguous`.
