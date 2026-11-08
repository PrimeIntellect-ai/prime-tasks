scipy.signal.istft error with numpy window
### Description

`jax.signal.istft` raises `ValueError: The truth value of an array with more than one element is ambiguous. Use a.any() or a.all()` when the `window` argument is set to a numpy array.

```python
import jax.numpy as jnp
import numpy as np

Zxx = jnp.ones((257, 41))
nperseg = 512
window = np.ones(nperseg)
jax.scipy.signal.istft(Zxx, fs=1024, nperseg=nperseg, window=window)
```

[HIDDEN]


### System info (python version, jaxlib version, accelerator, etc.)

```
jax:    0.6.0
jaxlib: 0.6.0
numpy:  2.2.5
python: 3.10.14 (main, Aug 14 2024, 05:11:29) [Clang 18.1.8 ]
device info: NVIDIA GeForce GTX 1660 Ti-1, 1 local devices"
process_count: 1
platform: uname_result(system='Linux', node='Legion-5', release='6.11.0-21-generic', version='#21~24.04.1-Ubuntu SMP PREEMPT_DYNAMIC Mon Feb 24 16:52:15 UTC 2', machine='x86_64')


$ nvidia-smi
Wed May  7 11:44:14 2025
+---------------------------------------------------------------------------------------+
| NVIDIA-SMI 535.247.01             Driver Version: 535.247.01   CUDA Version: 12.2     |
|-----------------------------------------+----------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |         Memory-Usage | GPU-Util  Compute M. |
|                                         |                      |               MIG M. |
|=========================================+======================+======================|
|   0  NVIDIA GeForce GTX 1660 Ti     On  | 00000000:01:00.0  On |                  N[/](https://file+.vscode-resource.vscode-cdn.net/)A |
| N/A   44C    P8               6W [/](https://file+.vscode-resource.vscode-cdn.net/)  80W |   4599MiB /  6144MiB |     17%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+

+---------------------------------------------------------------------------------------+
| Processes:                                                                            |
|  GPU   GI   CI        PID   Type   Process name                            GPU Memory |
|        ID   ID                                                             Usage      |
|=======================================================================================|
|    0   N/A  N/A      2572      G   [/usr/lib/xorg/Xorg](https://file+.vscode-resource.vscode-cdn.net/usr/lib/xorg/Xorg)                           45MiB |
|    0   N/A  N/A     27839      C   .../multivarie_python/.venv/bin/python     4550MiB |
+---------------------------------------------------------------------------------------+
```

### Additional contract requirements

- `jax.scipy.signal.istft` must accept a NumPy array as its `window` argument and proceed with the requested operation without raising an ambiguous truth-value error.
