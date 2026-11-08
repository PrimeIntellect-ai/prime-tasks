[BUG] `adjoint_metric_tensor` does not work with `StatePrep` operations
### Expected behavior

`adjoint_metric_tensor` can be applied to a circuit containing a `StatePrep` operation.

### Actual behavior

It errors out, trying to find the matrix of `StatePrep`, as reported in [this discussion forum question](https://discuss.pennylane.ai/t/matrixundefinederror-when-using-qml-stateprep-with-qml-gradients-quantum-fisher/5186) by @joeybarreto.

### Additional information

[HIDDEN]

### Source code

```shell
import pennylane as qml
import numpy as np
from pennylane import numpy as pnp

Nq = 2
pnp.random.seed(42)
dev = qml.device('default.qubit', wires=Nq) #,shots=10

init_state = np.random.rand(2**Nq)
init_state /= np.linalg.norm(init_state)
print("|init> =", init_state)

@qml.qnode(dev)
def circuit(angles):
    qml.StatePrep(init_state, wires=range(Nq))
    # qml.Hadamard(0)
    qml.RX(angles[0], wires=0)
    qml.RY(angles[1], wires=1)

    return qml.expval(qml.PauliZ(0))

angles = 2*pnp.pi*pnp.random.uniform(size=(2,), requires_grad=True)

print(circuit(angles))

grad = qml.grad(circuit)(angles)
print("grad =", grad)

qfim = qml.gradients.quantum_fisher(circuit)(angles)
print(qfim.shape)
```


### Tracebacks

```shell
---------------------------------------------------------------------------
MatrixUndefinedError                      Traceback (most recent call last)
Cell In[60], line 28
     25 grad = qml.grad(circuit)(angles)
     26 print("grad =", grad)
---> 28 qfim = qml.gradients.quantum_fisher(circuit)(angles)
     29 print(qfim.shape)

File ~/miniconda3/envs/lanl/lib/python3.12/site-packages/pennylane/workflow/qnode.py:1020, in QNode.__call__(self, *args, **kwargs)
   1018 if qml.capture.enabled():
   1019     return qml.capture.qnode_call(self, *args, **kwargs)
-> 1020 return self._impl_call(*args, **kwargs)

File ~/miniconda3/envs/lanl/lib/python3.12/site-packages/pennylane/workflow/qnode.py:1008, in QNode._impl_call(self, *args, **kwargs)
   1005 self._update_gradient_fn(shots=override_shots, tape=self._tape)
   1007 try:
-> 1008     res = self._execution_component(args, kwargs, override_shots=override_shots)
   1009 finally:
   1010     if old_interface == "auto":

File ~/miniconda3/envs/lanl/lib/python3.12/site-packages/pennylane/workflow/qnode.py:957, in QNode._execution_component(self, args, kwargs, override_shots)
    951     warnings.filterwarnings(
    952         action="ignore",
    953         message=r".*argument is deprecated and will be removed in version 0.39.*",
    954         category=qml.PennyLaneDeprecationWarning,
    955     )
    956     # pylint: disable=unexpected-keyword-arg
--> 957     res = qml.execute(
    958         (self._tape,),
    959         device=self.device,
    960         gradient_fn=self.gradient_fn,
    961         interface=self.interface,
    962         transform_program=full_transform_program,
    963         inner_transform=inner_transform_program,
    964         config=config,
    965         gradient_kwargs=self.gradient_kwargs,
    966         override_shots=override_shots,
    967         **execute_kwargs,
    968     )
    969 res = res[0]
    971 # convert result to the interface in case the qfunc has no parameters

File ~/miniconda3/envs/lanl/lib/python3.12/site-packages/pennylane/workflow/execution.py:653, in execute(tapes, device, gradient_fn, interface, transform_program, inner_transform, config, grad_on_execution, gradient_kwargs, cache, cachesize, max_diff, override_shots, expand_fn, max_expansion, device_batch_transform, device_vjp, mcm_config)
    647 if not device_batch_transform:
    648     warnings.warn(
    649         "Device batch transforms cannot be turned off with the new device interface.",
    650         UserWarning,
    651     )
--> 653 tapes, post_processing = transform_program(tapes)
    655 if transform_program.is_informative:
    656     return post_processing(tapes)

File ~/miniconda3/envs/lanl/lib/python3.12/site-packages/pennylane/transforms/core/transform_program.py:515, in TransformProgram.__call__(self, tapes)
    513 if self._argnums is not None and self._argnums[i] is not None:
    514     tape.trainable_params = self._argnums[i][j]
--> 515 new_tapes, fn = transform(tape, *targs, **tkwargs)
    516 execution_tapes.extend(new_tapes)
    518 fns.append(fn)

File ~/miniconda3/envs/lanl/lib/python3.12/site-packages/pennylane/gradients/fisher.py:382, in quantum_fisher(tape, device, *args, **kwargs)
    378         return 4 * processing_fn(res)
    380     return tapes, processing_fn_multiply
--> 382 res = adjoint_metric_tensor(tape, *args, **kwargs)
    384 def processing_fn_multiply(r):  # pylint: disable=function-redefined
    385     r = qml.math.stack(r)

File ~/miniconda3/envs/lanl/lib/python3.12/site-packages/pennylane/transforms/core/transform_dispatcher.py:116, in TransformDispatcher.__call__(self, *targs, **tkwargs)
    113         transformed_tapes, processing_fn = self._transform(obj, *targs, **tkwargs)
    115     if self.is_informative:
--> 116         return processing_fn(transformed_tapes)
    117     return transformed_tapes, processing_fn
    119 if isinstance(obj, qml.QNode):

File ~/miniconda3/envs/lanl/lib/python3.12/site-packages/pennylane/transforms/core/transform_dispatcher.py:109, in TransformDispatcher.__call__.<locals>.processing_fn(results)
    108 def processing_fn(results):
--> 109     processed_results = [fn(results[slice]) for fn, slice in processing_and_sclices]
    110     return expand_processing(processed_results)

File ~/miniconda3/envs/lanl/lib/python3.12/site-packages/pennylane/gradients/adjoint_metric_tensor.py:188, in adjoint_metric_tensor.<locals>.processing_fn(tapes)
    185 T = qml.math.convert_like(qml.math.zeros((tape.num_params,)), like_real)
    187 for op in group_after_trainable_op[-1]:
--> 188     psi = qml.devices.qubit.apply_operation(op, psi)
    190 for j, outer_op in enumerate(trainable_operations):
    191     generator_1, prefactor_1 = qml.generator(outer_op)

File ~/miniconda3/envs/lanl/lib/python3.12/functools.py:909, in singledispatch.<locals>.wrapper(*args, **kw)
    905 if not args:
    906     raise TypeError(f'{funcname} requires at least '
    907                     '1 positional argument')
--> 909 return dispatch(args[0].__class__)(*args, **kw)

File ~/miniconda3/envs/lanl/lib/python3.12/site-packages/pennylane/devices/qubit/apply_operation.py:218, in apply_operation(op, state, is_state_batched, debugger, **_)
    152 @singledispatch
    153 def apply_operation(
    154     op: qml.operation.Operator,
   (...)
    158     **_,
    159 ):
    160     """Apply and operator to a given state.
    161
    162     Args:
   (...)
    216
    217     """
--> 218     return _apply_operation_default(op, state, is_state_batched, debugger)

File ~/miniconda3/envs/lanl/lib/python3.12/site-packages/pennylane/devices/qubit/apply_operation.py:228, in _apply_operation_default(op, state, is_state_batched, debugger)
    222 """The default behaviour of apply_operation, accessed through the standard dispatch
    223 of apply_operation, as well as conditionally in other dispatches."""
    224 if (
    225     len(op.wires) < EINSUM_OP_WIRECOUNT_PERF_THRESHOLD
    226     and math.ndim(state) < EINSUM_STATE_WIRECOUNT_PERF_THRESHOLD
    227 ) or (op.batch_size and is_state_batched):
--> 228     return apply_operation_einsum(op, state, is_state_batched=is_state_batched)
    229 return apply_operation_tensordot(op, state, is_state_batched=is_state_batched)

File ~/miniconda3/envs/lanl/lib/python3.12/site-packages/pennylane/devices/qubit/apply_operation.py:74, in apply_operation_einsum(op, state, is_state_batched)
     62 def apply_operation_einsum(op: qml.operation.Operator, state, is_state_batched: bool = False):
     63     """Apply ``Operator`` to ``state`` using ``einsum``. This is more efficent at lower qubit
     64     numbers.
     65
   (...)
     72         array[complex]: output_state
     73     """
---> 74     mat = qml.math.cast_like(op.matrix(), 1j)
     76     total_indices = len(state.shape) - is_state_batched
     77     num_indices = len(op.wires)

File ~/miniconda3/envs/lanl/lib/python3.12/site-packages/pennylane/operation.py:838, in Operator.matrix(self, wire_order)
    818 def matrix(self, wire_order: Optional[WiresLike] = None) -> TensorLike:
    819     r"""Representation of the operator as a matrix in the computational basis.
    820
    821     If ``wire_order`` is provided, the numerical representation considers the position of the
   (...)
    836         tensor_like: matrix representation
    837     """
--> 838     canonical_matrix = self.compute_matrix(*self.parameters, **self.hyperparameters)
    840     if (
    841         wire_order is None
    842         or self.wires == Wires(wire_order)
   (...)
    846         )
    847     ):
    848         return canonical_matrix

File ~/miniconda3/envs/lanl/lib/python3.12/site-packages/pennylane/operation.py:807, in Operator.compute_matrix(*params, **hyperparams)
    789 @staticmethod
    790 def compute_matrix(
    791     *params: TensorLike, **hyperparams: dict[str, Any]
    792 ) -> TensorLike:  # pylint:disable=unused-argument
    793     r"""Representation of the operator as a canonical matrix in the computational basis (static method).
    794
    795     The canonical matrix is the textbook matrix representation that does not consider wires.
   (...)
    805         tensor_like: matrix representation
    806     """
--> 807     raise MatrixUndefinedError

MatrixUndefinedError:
```


### System information

```shell
pl dev
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.

### Additional contract requirements

- Applying `adjoint_metric_tensor` to a circuit containing a `StatePrep` operation must succeed.
