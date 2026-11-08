Nelder-Mead method in scipy_optimizer.py should support bounds
### Description

The Nelder-Mead method for scipy supports bounds at least as of scipy 1.11.
[https://docs.scipy.org/doc/scipy/reference/optimize.minimize-neldermead.html](url)

[HIDDEN]

### Example

[nelder_mead_test.txt](https://github.com/OpenMDAO/OpenMDAO/files/13907649/nelder_mead_test.txt)

Objectives
{'dummy_function.y': array([-4.01734511e+60])}

/home0/zfrederi/OpenMDAO/openmdao/drivers/scipy_optimizer.py:472: RuntimeWarning: Maximum number of iterations has been exceeded.
  result = minimize(self._objfunc, x_init,
Optimization FAILED.
Maximum number of iterations has been exceeded.

### OpenMDAO Version

3.30.1.dev0

### Relevant environment information

scipy 1.11.2

### Additional contract requirements

- When using Nelder-Mead with bounded design variables, the optimization must honor their declared lower and upper bounds.
