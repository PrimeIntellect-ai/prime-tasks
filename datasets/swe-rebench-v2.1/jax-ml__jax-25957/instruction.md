jax_debug_key_reuse incorrectly raises error
### Description

The following code raises error `KeyReuseError: Previously-consumed key passed to random_split at index 0` despite that we haven't used key2 yet.

```python
import jax; jax.config.update('jax_debug_key_reuse', True)
key = jax.random.key(0)
key1, key2 = jax.random.split(key)
_, key2 = jax.device_put((key1, key2))
jax.random.split(key2)
```

### System info (python version, jaxlib version, accelerator, etc.)

```
jax:    0.4.36
jaxlib: 0.4.36
numpy:  1.26.4
python: 3.12.7 (main, Oct  1 2024, 02:05:46) [Clang 16.0.0 (clang-1600.0.26.3)]
device info: cpu-1, 1 local devices"
process_count: 1
platform: uname_result(system='Darwin', node='phandu-mac.roam.internal', release='24.2.0', version='Darwin Kernel Version 24.2.0: Fri Dec  6 19:02:41 PST 2024; root:xnu-11215.61.5~2/RELEASE_ARM64_T6030', machine='arm64')
```
