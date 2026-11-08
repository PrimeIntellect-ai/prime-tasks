Modules annotated with jaxtyping somtimes does not unpickle correctly
```python
import pickle

import equinox as eqx
from jax import Array
from jax import numpy as jnp
from jax import tree_util as jtu
from jaxtyping import Float


class A(eqx.Module):
    x: Float[Array, ""]  # works if replaced with just Array


def main():
    b = A(jnp.array(1.0))

    tree = jtu.tree_structure(b)
    b = tree.unflatten([jnp.array(2.0)])  # works if remove this line

    b2 = pickle.loads(pickle.dumps(b))

    # PyTreeDef(CustomNode(A[('x',), (), ()], [*]))
    print(jtu.tree_structure(b2))
    # PyTreeDef(CustomNode(A[('x',), (), ()], [*]))
    print(tree)

    # AssertionError
    assert jtu.tree_structure(b2) == tree
```

```
jax 0.5.3
equinox 0.11.12
jaxtyping 0.2.38
```
