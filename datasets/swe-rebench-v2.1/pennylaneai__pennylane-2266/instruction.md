[BUG] decomposition of `RandomLayers` broken
Upon executing the documentation example of `qml.RandomLayers`,

```python
import pennylane as qml
import numpy as np

dev = qml.device("default.qubit", wires=2)
weights = [[0.1, -2.1, 1.4]]

@qml.qnode(dev)
def circuit1(weights):
    qml.RandomLayers(weights=weights, wires=range(2))
    return qml.expval(qml.PauliZ(0))

circuit1(weights)
```
The following error is raised:

```
---------------------------------------------------------------------------
TypeError                                 Traceback (most recent call last)
File ~/Prog/pennylane/pennylane/operation.py:1096, in Operator.expand(self)
   1095 try:
-> 1096     self.decomposition()
   1098 except TypeError:

File ~/Prog/pennylane/pennylane/operation.py:989, in Operator.decomposition(self)
    978 r"""Representation of the operator as a product of other operators.
    979
    980 .. math:: O = O_1 O_2 \dots O_n
   (...)
    987     list[Operator]: decomposition of the operator
    988 """
--> 989 return self.compute_decomposition(
    990     *self.parameters, wires=self.wires, **self.hyperparameters
    991 )

File ~/Prog/pennylane/pennylane/templates/layers/random.py:260, in RandomLayers.compute_decomposition(weights, wires, ratio_imprimitive, imprimitive, rotations, seed)
    259 rnd_wire = wires.select_random(1)
--> 260 op_list.append(gate([HIDDEN], wires=rnd_wire))
    261 i += 1

TypeError: list indices must be integers or slices, not tuple

During handling of the above exception, another exception occurred:

TypeError                                 Traceback (most recent call last)
Input In [19], in <cell line: 1>()
----> 1 circuit1(weights)

File ~/Prog/pennylane/pennylane/qnode.py:560, in QNode.__call__(self, *args, **kwargs)
    553 using_custom_cache = (
    554     hasattr(cache, "__getitem__")
    555     and hasattr(cache, "__setitem__")
    556     and hasattr(cache, "__delitem__")
    557 )
    558 self._tape_cached = using_custom_cache and self.tape.hash in cache
--> 560 res = qml.execute(
    561     [self.tape],
    562     device=self.device,
    563     gradient_fn=self.gradient_fn,
    564     interface=self.interface,
    565     gradient_kwargs=self.gradient_kwargs,
    566     override_shots=override_shots,
    567     **self.execute_kwargs,
    568 )
    570 if autograd.isinstance(res, (tuple, list)) and len(res) == 1:
    571     # If a device batch transform was applied, we need to 'unpack'
    572     # the returned tuple/list to a float.
   (...)
    579     # TODO: find a more explicit way of determining that a batch transform
    580     # was applied.
    582     res = res[0]

File ~/Prog/pennylane/pennylane/interfaces/batch/__init__.py:342, in execute(tapes, device, gradient_fn, interface, mode, gradient_kwargs, cache, cachesize, max_diff, override_shots, expand_fn, max_expansion, device_batch_transform)
    338     return batch_fn(res)
    340 if gradient_fn == "backprop" or interface is None:
    341     return batch_fn(
--> 342         cache_execute(batch_execute, cache, return_tuple=False, expand_fn=expand_fn)(tapes)
    343     )
    345 # the default execution function is batch_execute
    346 execute_fn = cache_execute(batch_execute, cache, expand_fn=expand_fn)

File ~/Prog/pennylane/pennylane/interfaces/batch/__init__.py:173, in cache_execute.<locals>.wrapper(tapes, **kwargs)
    169         return (res, []) if return_tuple else res
    171 else:
    172     # execute all unique tapes that do not exist in the cache
--> 173     res = fn(execution_tapes.values(), **kwargs)
    175 final_res = []
    177 for i, tape in enumerate(tapes):

File ~/Prog/pennylane/pennylane/interfaces/batch/__init__.py:124, in cache_execute.<locals>.fn(tapes, **kwargs)
    123 def fn(tapes, **kwargs):  # pylint: disable=function-redefined
--> 124     tapes = [expand_fn(tape) for tape in tapes]
    125     return original_fn(tapes, **kwargs)

File ~/Prog/pennylane/pennylane/interfaces/batch/__init__.py:124, in <listcomp>(.0)
    123 def fn(tapes, **kwargs):  # pylint: disable=function-redefined
--> 124     tapes = [expand_fn(tape) for tape in tapes]
    125     return original_fn(tapes, **kwargs)

File ~/Prog/pennylane/pennylane/interfaces/batch/__init__.py:325, in execute.<locals>.<lambda>(tape)
    322 batch_execute = set_shots(device, override_shots)(device.batch_execute)
    324 if expand_fn == "device":
--> 325     expand_fn = lambda tape: device.expand_fn(tape, max_expansion=max_expansion)
    327 if gradient_fn is None:
    328     # don't unwrap if it's an interface device
    329     if "passthru_interface" in device.capabilities():

File ~/Prog/pennylane/pennylane/_device.py:658, in Device.expand_fn(self, circuit, max_expansion)
    655 if self.custom_expand_fn is not None:
    656     return self.custom_expand_fn(circuit, max_expansion=max_expansion)
--> 658 return self.default_expand_fn(circuit, max_expansion=max_expansion)

File ~/Prog/pennylane/pennylane/_device.py:633, in Device.default_expand_fn(self, circuit, max_expansion)
    630 ops_not_supported = not all(self.stopping_condition(op) for op in circuit.operations)
    632 if ops_not_supported or obs_on_same_wire:
--> 633     circuit = circuit.expand(depth=max_expansion, stop_at=self.stopping_condition)
    635 return circuit

File ~/Prog/pennylane/pennylane/tape/tape.py:563, in QuantumTape.expand(self, depth, stop_at, expand_measurements)
    515 def expand(self, depth=1, stop_at=None, expand_measurements=False):
    516     """Expand all operations in the processed queue to a specific depth.
    517
    518     Args:
   (...)
    561     RY(0.2, wires=['a'])]
    562     """
--> 563     new_tape = expand_tape(
    564         self, depth=depth, stop_at=stop_at, expand_measurements=expand_measurements
    565     )
    566     new_tape._update()
    567     return new_tape

File ~/Prog/pennylane/pennylane/tape/tape.py:197, in expand_tape(tape, depth, stop_at, expand_measurements)
    194 if isinstance(obj, (qml.operation.Operation, qml.measure.MeasurementProcess)):
    195     # Object is an operation; query it for its expansion
    196     try:
--> 197         obj = obj.expand()
    198     except DecompositionUndefinedError:
    199         # Object does not define an expansion; treat this as
    200         # a stopping condition.
    201         getattr(new_tape, queue).append(obj)

File ~/Prog/pennylane/pennylane/operation.py:1102, in Operator.expand(self)
   1100             self.decomposition(wires=self.wires)
   1101         else:
-> 1102             self.decomposition(*self.parameters, wires=self.wires)
   1104         warnings.warn(
   1105             "Operator.decomposition() is now an instance method, and no longer accepts parameters. "
   1106             "Either define the static method 'compute_decomposition' instead, or use "
   1107             "'self.wires' and 'self.parameters'.",
   1108             UserWarning,
   1109         )
   1111 if not self.data:
   1112     # original operation has no trainable parameters

TypeError: decomposition() got an unexpected keyword argument 'wires'

```

### Additional contract requirements

- `qml.RandomLayers` must decompose successfully when its weights are supplied as a nested Python list, allowing the reported documentation example to execute.
