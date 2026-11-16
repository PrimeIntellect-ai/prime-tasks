[BUG] `defer_measurements` does not work with `qml.cond` applied to controlled gates
### Expected behavior

`qml.cond` can be applied to any valid `Operation` and `defer_measurements` can deal with the resulting operation as well.

### Actual behavior

Using `qml.cond` on a controlled operation and deferring measurements afterwards raises an error.

### Additional information

The control values seem to be the problem, with defaults of whether we use lists or tuples for those differing between parts of the codebase, apparently.

### Source code

```shell
dev = qml.device("default.qubit")#, shots= 100) # with shots the code runs because defer_measurements is no longer used by default.

@qml.qnode(dev)
def node(x):
    qml.Hadamard(0)
    mcm1 = qml.measure(0)
    qml.cond(mcm1, qml.CRY)(x, wires=(0, 1))
    return qml.expval(qml.Z(1))

node(0.6)
```


### Tracebacks

```shell
---------------------------------------------------------------------------
TypeError                                 Traceback (most recent call last)
Cell In[13], line 10
      7     qml.cond(mcm1, qml.CRY)(x, wires=(0, 1))
      8     return qml.expval(qml.Z(1))
---> 10 node(0.6)

File ~/repos/pennylane/pennylane/workflow/qnode.py:1098, in QNode.__call__(self, *args, **kwargs)
   1095 self._update_gradient_fn(shots=override_shots, tape=self._tape)
   1097 try:
-> 1098     res = self._execution_component(args, kwargs, override_shots=override_shots)
   1099 finally:
   1100     if old_interface == "auto":

File ~/repos/pennylane/pennylane/workflow/qnode.py:1052, in QNode._execution_component(self, args, kwargs, override_shots)
   1049 full_transform_program.prune_dynamic_transform()
   1051 # pylint: disable=unexpected-keyword-arg
-> 1052 res = qml.execute(
   1053     (self._tape,),
   1054     device=self.device,
   1055     gradient_fn=self.gradient_fn,
   1056     interface=self.interface,
   1057     transform_program=full_transform_program,
   1058     config=config,
   1059     gradient_kwargs=self.gradient_kwargs,
   1060     override_shots=override_shots,
   1061     **self.execute_kwargs,
   1062 )
   1063 res = res[0]
   1065 # convert result to the interface in case the qfunc has no parameters

File ~/repos/pennylane/pennylane/workflow/execution.py:601, in execute(tapes, device, gradient_fn, interface, transform_program, config, grad_on_execution, gradient_kwargs, cache, cachesize, max_diff, override_shots, expand_fn, max_expansion, device_batch_transform, device_vjp)
    596     if not device_batch_transform:
    597         warnings.warn(
    598             "device batch transforms cannot be turned off with the new device interface.",
    599             UserWarning,
    600         )
--> 601     tapes, post_processing = transform_program(tapes)
    602 else:
    603     # TODO: Remove once old device are removed
    604     tapes, program_post_processing = transform_program(tapes)

File ~/repos/pennylane/pennylane/transforms/core/transform_program.py:509, in TransformProgram.__call__(self, tapes)
    507 if self._argnums is not None and self._argnums[i] is not None:
    508     tape.trainable_params = self._argnums[i][j]
--> 509 new_tapes, fn = transform(tape, *targs, **tkwargs)
    510 execution_tapes.extend(new_tapes)
    512 fns.append(fn)

File ~/repos/pennylane/pennylane/devices/preprocess.py:158, in mid_circuit_measurements(tape, device)
    156 if tape.shots:
    157     return qml.dynamic_one_shot(tape)
--> 158 return qml.defer_measurements(tape, device=device)

File ~/repos/pennylane/pennylane/transforms/core/transform_dispatcher.py:113, in TransformDispatcher.__call__(self, *targs, **tkwargs)
    110         return expand_processing(processed_results)
    112 else:
--> 113     transformed_tapes, processing_fn = self._transform(obj, *targs, **tkwargs)
    115 if self.is_informative:
    116     return processing_fn(transformed_tapes)

File ~/repos/pennylane/pennylane/transforms/defer_measurements.py:336, in defer_measurements(tape, reduce_postselected, **kwargs)
    334 elif op.__class__.__name__ == "Conditional":
    335     with QueuingManager.stop_recording():
--> 336         new_operations.extend(_add_control_gate(op, control_wires, reduce_postselected))
    337 else:
    338     new_operations.append(op)

File ~/repos/pennylane/pennylane/transforms/defer_measurements.py:411, in _add_control_gate(op, control_wires, reduce_postselected)
    409             new_ops.append(op.then_op)
    410             continue
--> 411         qscript = qml.tape.make_qscript(
    412             ctrl(
    413                 lambda: qml.apply(op.then_op),  # pylint: disable=cell-var-from-loop
    414                 control=Wires(control),
    415                 control_values=branch,
    416             )
    417         )()
    418         new_ops.extend(qscript.circuit)
    419 return new_ops

File ~/repos/pennylane/pennylane/tape/qscript.py:1213, in make_qscript.<locals>.wrapper(*args, **kwargs)
   1211 def wrapper(*args, **kwargs):
   1212     with AnnotatedQueue() as q:
-> 1213         fn(*args, **kwargs)
   1215     return QuantumScript.from_queue(q, shots)

File ~/repos/pennylane/pennylane/ops/op_math/controlled.py:190, in create_controlled_op.<locals>.wrapper(*args, **kwargs)
    187 if flip_control_on_zero:
    188     _ = [qml.X(w) for w, val in zip(control, control_values) if not val]
--> 190 _ = [
    191     ctrl(op, control=control, control_values=op_control_values, work_wires=work_wires)
    192     for op in qscript.operations
    193 ]
    195 if flip_control_on_zero:
    196     _ = [qml.X(w) for w, val in zip(control, control_values) if not val]

File ~/repos/pennylane/pennylane/ops/op_math/controlled.py:191, in <listcomp>(.0)
    187 if flip_control_on_zero:
    188     _ = [qml.X(w) for w, val in zip(control, control_values) if not val]
    190 _ = [
--> 191     ctrl(op, control=control, control_values=op_control_values, work_wires=work_wires)
    192     for op in qscript.operations
    193 ]
    195 if flip_control_on_zero:
    196     _ = [qml.X(w) for w, val in zip(control, control_values) if not val]

File ~/repos/pennylane/pennylane/ops/op_math/controlled.py:132, in ctrl(op, control, control_values, work_wires)
    130 if qml.math.is_abstract(op):
    131     return Controlled(op, control, control_values=control_values, work_wires=work_wires)
--> 132 return create_controlled_op(op, control, control_values=control_values, work_wires=work_wires)

File ~/repos/pennylane/pennylane/ops/op_math/controlled.py:164, in create_controlled_op(op, control, control_values, work_wires)
    159 if isinstance(op, Controlled):
    160     work_wires = work_wires or []
    161     return ctrl(
    162         op.base,
    163         control=control + op.control_wires,
--> 164 [HIDDEN]
    165         work_wires=work_wires + op.work_wires,
    166     )
    168 if isinstance(op, Operator):
    169     return Controlled(
    170         op, control_wires=control, control_values=control_values, work_wires=work_wires
    171     )

TypeError: can only concatenate tuple (not "list") to tuple
```


### System information

```shell
pl dev
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.
