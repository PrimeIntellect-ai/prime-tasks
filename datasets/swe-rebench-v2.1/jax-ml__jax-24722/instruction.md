Tracers are now hashable.
### Description

`jax.jit(hash)(1)` does not error on any recent version of JAX. I went back and checked and the last time this seems to have produced an error was `0.4.8`.

Is this intended? It means that tracers do not duck-type as either concrete JAX arrays or as numpy arrays. In particular see #21825, which this caused.

### System info (python version, jaxlib version, accelerator, etc.)

jax:    0.4.29
jaxlib: 0.4.29
numpy:  1.26.4
python: 3.11.9 (main, Apr 19 2024, 11:43:47) [Clang 14.0.6 ]
jax.devices (1 total, 1 local): [CpuDevice(id=0)]
process_count: 1
platform: uname_result(system='Darwin', node='Air.localdomain', release='22.5.0', version='Darwin Kernel Version 22.5.0: Mon Apr 24 20:52:43 PDT 2023; root:xnu-8796.121.2~5/RELEASE_ARM64_T8112', machine='arm64')

### Additional contract requirements

- Hashing a JAX tracer must raise `TypeError`, making tracers unhashable like concrete JAX arrays. This includes hashing a tracer while tracing a `jax.jit` computation.
