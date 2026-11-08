shard_map - NotImplementedError: No replication rule for while
### Description

Fixing the following

`NotImplementedError: No replication rule for while. As a workaround, pass the check_rep=False argument to shard_map. To get this fixed, open an issue at https://github.com/jax-ml/jax/issues`

would help me to use shard_map in my simulation code (it contains while-loops (`jax.lax.while_loop`) for time-integration purposes (with adaptive but global time steps, the minimum of the local ones) as well as fixed-point iterations within each time-step).

### System info (python version, jaxlib version, accelerator, etc.)

jax:    0.5.1
jaxlib: 0.5.1
numpy:  2.0.2
python: 3.10.15 | packaged by conda-forge
