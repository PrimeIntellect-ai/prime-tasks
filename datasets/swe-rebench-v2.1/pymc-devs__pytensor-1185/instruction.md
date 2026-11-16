Bug in einsum
### Description

```python
import pytensor.tensor as pt

pt.einsum("..., ..., ...-> ...", pt.ones(2), pt.ones(2), pt.ones(2))
# ValueError: Each step of einsum must have 1 or 2 operands, got 3
```

Found when trying to add einops support: https://github.com/arogozhnikov/einops/pull/362
