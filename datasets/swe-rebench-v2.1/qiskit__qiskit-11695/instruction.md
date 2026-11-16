Default values for `approximation_degree` differ in `transpile` and `generate_preset_pass_manager`
### Environment

- **Qiskit version**: 0.45
- **Python version**:
- **Operating system**:


### What is happening?

The `transpile` function has a default value of `approximation_degree=1.0` while the `generate_preset_pass_manager` function has `approximation_degree=None`. This can lead to drastically different default behavior when transpiling with these two functions on certain backends which was found by some recent researchers using the pass manager based code.

### How can we reproduce the issue?

To quote the example I was given:
> we had circuits with ~700 gates when  using v1 backends and/or transpile, but this dropped down to ~200 gates when using the preset pm.
on top of this, the approximation is also dependent on the actual 2Q unitary.

### What should happen?

The default values should be consistent between `transpile` and the preset pass manager.

### Any suggestions?

I believe the intended behavior is what is done in `transpile` (no approximation), so [HIDDEN]

### Additional contract requirements

- Calling `generate_preset_pass_manager` without an `approximation_degree` argument must use the same default approximation behaviour as `transpile`, i.e. `approximation_degree=1.0`. For a backend target at optimization level 3 with a fixed `seed_transpiler`, the circuit returned by the preset pass manager's `run` must equal the circuit returned by `transpile` with the same arguments.
