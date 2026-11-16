BUG  benchopt info fails when the safe import context is not named `import_ctx`
benchopt info tells me mne is installed, but it is not. Notice I am running directly from the `benchopt_lasso` environment.

```
(benchopt_lasso) ➜  lasso git:(bench) ✗ benchopt info . -d meg
Info regarding the benchmark 'lasso'
WARNING: astropy not found, will default to scipy for convolution
----------
# DATASETS
----------
## MEG
✓ available in 'running env'
> requirements:
    conda install -c conda-forge mne
----------
(benchopt_lasso) ➜  lasso git:(bench) ✗ ipython
Python 3.9.12 | packaged by conda-forge | (main, Mar 24 2022, 23:22:55)
Type 'copyright', 'credits' or 'license' for more information
IPython 8.3.0 -- An enhanced Interactive Python. Type '?' for help.

In [1]: import mne
---------------------------------------------------------------------------
ModuleNotFoundError                       Traceback (most recent call last)
Input In [1], in <cell line: 1>()
----> 1 import mne

ModuleNotFoundError: No module named 'mne'
```

from https://github.com/benchopt/benchmark_lasso/pull/84 (maybe an issue in my MEG Dataset class ?

@tanglef
