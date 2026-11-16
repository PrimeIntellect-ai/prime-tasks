get_all_specs not compatible with subclassing
[nb_conda_kernels](https://github.com/Anaconda-Platform/nb_conda_kernels) subclasses KernelSpecManager to find conda kernels. It does so by overriding `find_kernel_specs` to return its name list and resource directories, and `get_kernel_spec` to return the specs themselves.

We've added `.get_all_specs` as a simpler API to get all of the specs without separately finding and loading them. [HIDDEN]

Now, one option is for custom kernelspec managers to implement all three methods - find_kernel_specs, get_all_specs, and get_kernel_spec, but this is a backward-incompatible change, and I think we should consider it a bug.

I think we should ensure that `.get_all_specs` works for KSM subclasses that have only implemented the public methods `.find_kernel_specs` and `.get_kernel_spec` to fix this backward-incompatibility, and push that out in a bugfix release.

cc @dartdog who reported the issue

### Additional contract requirements

- `get_all_specs()` must return the available specs for names discovered by `find_kernel_specs()` when a `KernelSpecManager` subclass implements the public `find_kernel_specs()` and `get_kernel_spec()` methods without overriding `get_all_specs()`.
