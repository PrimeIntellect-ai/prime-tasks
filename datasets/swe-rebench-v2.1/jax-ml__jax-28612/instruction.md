`jax.numpy.linalg.matrix_power` brings different results with `numpy.linalg.matrix_power`
### Description

I found that `jax.numpy.linalg.matrix_power` brings different results with `numpy.linalg.matrix_power` in following case.
I think this may be a bug in `JAX`.

```py
import numpy as np
import jax.numpy as jnp

print(np.linalg.matrix_power(np.array([[True,True], [False,True]]), 2))
print(jnp.linalg.matrix_power(jnp.array([[True, True], [False, True]]), 2))
```

Output:
```bash
[[ True  True]
 [False  True]]
[[1. 2.]
 [0. 1.]]
```

### System info (python version, jaxlib version, accelerator, etc.)

```
jax:    0.6.0
jaxlib: 0.6.0
numpy:  2.2.3
python: 3.10.12 (main, Feb  4 2025, 14:57:36) [GCC 11.4.0]
device info: NVIDIA GeForce RTX 4090-1, 1 local devices"
process_count: 1
platform: uname_result(system='Linux', node='4db45dc420f8', release='6.11.0-25-generic', version='#25~24.04.1-Ubuntu SMP PREEMPT_DYNAMIC Tue Apr 15 17:20:50 UTC 2', machine='x86_64')


$ nvidia-smi
Wed May  7 16:26:08 2025
+---------------------------------------------------------------------------------------+
| NVIDIA-SMI 535.230.02             Driver Version: 535.230.02   CUDA Version: 12.2     |
|-----------------------------------------+----------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |         Memory-Usage | GPU-Util  Compute M. |
|                                         |                      |               MIG M. |
|=========================================+======================+======================|
|   0  NVIDIA GeForce RTX 4090        Off | 00000000:01:00.0 Off |                  Off |
| 36%   32C    P2              36W / 450W |    407MiB / 24564MiB |      1%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+

+---------------------------------------------------------------------------------------+
| Processes:                                                                            |
|  GPU   GI   CI        PID   Type   Process name                            GPU Memory |
|        ID   ID                                                             Usage      |
|=======================================================================================|
+---------------------------------------------------------------------------------------+
```
