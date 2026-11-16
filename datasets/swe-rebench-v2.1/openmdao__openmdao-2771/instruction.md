Problem with get_io_metadata: `discrete` is always set to `True`
### Description

`get_io_metadata()` seems to return `discrete: True` for all variables even if no discrete variable is declared.

### Example

```python
import openmdao.api as om
from openmdao.test_suite.components.sellar_feature import SellarMDA

prob = om.Problem()
prob.model = SellarMDA()

prob.setup()
prob.set_solver_print(level=0)

prob.run_model()

print(prob.model.get_io_metadata(includes='x'))

# Result:
# {'cycle.d1.x': {'units': None, 'shape': (1,), 'size': 1, 'distributed': False, 'tags': set(), 'desc': '', 'shape_by_conn': False, 'copy_shape': None, 'has_src_indices': False, 'global_size': 1, 'global_shape': (1,), 'prom_name': 'x', 'discrete': True}, 'obj_cmp.x': {'units': None, 'shape': (1,), 'size': 1, 'distributed': False, 'tags': set(), 'desc': '', 'shape_by_conn': False, 'copy_shape': None, 'has_src_indices': False, 'global_size': 1, 'global_shape': (1,), 'prom_name': 'x', 'discrete': True}}
```


### OpenMDAO Version

3.21

### Relevant environment information

_No response_
