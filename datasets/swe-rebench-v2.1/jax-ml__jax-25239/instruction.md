Difference between numpy and jax.numpy in advanced indexing axes order
### Description

According to #15653, jax should match numpy with respect to advanced indexing.
There is a difference with empty ellipses.


```python
import numpy as np
a=np.ones((3,4,5))
print(a[:,(0,1),...,(0,1)].shape)
# (2, 3) # numpy

import jax.numpy as jnp
a=jnp.ones((3,4,5))
print(a[:,(0,1),...,(0,1)].shape)
# (3, 2) # jax

import torch
a=torch.ones(3,4,5)
print(a[:,(0,1),...,(0,1)].shape)
# torch.Size([3, 2]) # torch

print(np.__version__)
# 1.26.4. same result on 2.1.3

import jax
print(jax.__version__)
# 0.4.33
```



Numpy treats advanced indices separated by an ellipsis that does not consume any axes not as contiguous, whereas jax does  and subsequently does not move the new indices to the front..

### System info (python version, jaxlib version, accelerator, etc.)

```
jax:    0.4.33
jaxlib: 0.4.33
numpy:  1.26.4
python: 3.10.12 (main, Nov  6 2024, 20:22:13) [GCC 11.4.0]
jax.devices (1 total, 1 local): [CpuDevice(id=0)]
process_count: 1
platform: uname_result(system='Linux', node='151e18e640a6', release='6.1.85+', version='#1 SMP PREEMPT_DYNAMIC Thu Jun 27 21:05:47 UTC 2024', machine='x86_64')
```
