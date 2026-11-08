Recursively initialize Module parameters
Say I have an `ExactGP` called `gp`. It would be great if I could just do `gp.initialize(kwargs)` and all the parameters will be initialized recursively. This would allow us to put all the initialization values in one place.

Note that it would have to raise an error if there were a parameter name collision.

### Additional contract requirements

- The public method is `Module.initialize(self, **kwargs)` on `gpytorch.module.Module`. Each keyword argument key is either the name of a parameter of the module or a dot-separated path to a nested parameter (for example `likelihood.noise` or `covar_module.base_kernel.lengthscale`); the corresponding value is assigned to that parameter.
- Each value may be a `torch.Tensor`, a `float`, or an `int`; integer values are cast to float.
- `initialize` raises `AttributeError` if a supplied name does not correspond to any existing parameter.

- A dotted parameter path must not use the name of an existing parameter as a module component. Such a name collision raises an error.
