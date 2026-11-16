[BUG] Adjoint method does not respect global wires return types
### Expected behavior

Found by @Shiro-Raven:

The adjoint method _validation_ takes the same wires into account for measurements as forward execution unrelated to the adjoint method.

### Actual behavior

An error is raised.

### Additional information

[HIDDEN]
For measurements that rely on the device wires, because they act globally on "all" wires, this causes the error below.

### Source code

```shell
dev = qml.device("default.qubit", wires=2)


@qml.qnode(dev, diff_method="adjoint")
def circuit():
    return qml.state()


circuit()
```


### Tracebacks

```shell
---------------------------------------------------------------------------
ValueError                                Traceback (most recent call last)
Cell In[2], line 9
      4 @qml.qnode(dev, diff_method="adjoint")
      5 def circuit():
      6     return qml.state()
----> 9 circuit()

File ~/repos/pennylane/pennylane/workflow/qnode.py:1095, in QNode.__call__(self, *args, **kwargs)
   1092 self.construct(args, kwargs)
   1094 original_grad_fn = [self.gradient_fn, self.gradient_kwargs, self.device]
-> 1095 self._update_gradient_fn(shots=override_shots, tape=self._tape)
   1097 try:
   1098     res = self._execution_component(args, kwargs, override_shots=override_shots)

File ~/repos/pennylane/pennylane/workflow/qnode.py:604, in QNode._update_gradient_fn(self, shots, tape)
    597 if (
    598     self.device.name == "lightning.qubit"
    599     and qml.metric_tensor in self.transform_program
    600     and self.diff_method == "best"
    601 ):
    602     diff_method = "parameter-shift"
--> 604 self.gradient_fn, self.gradient_kwargs, self.device = self.get_gradient_fn(
    605     self._original_device, self.interface, diff_method, tape=tape
    606 )
    607 self.gradient_kwargs.update(self._user_gradient_kwargs or {})

File ~/repos/pennylane/pennylane/workflow/qnode.py:650, in QNode.get_gradient_fn(device, interface, diff_method, tape)
    648 config = _make_execution_config(None, diff_method)
    649 if isinstance(device, qml.devices.Device):
--> 650     if device.supports_derivatives(config, circuit=tape):
    651         new_config = device.preprocess(config)[1]
    652         return new_config.gradient_method, {}, device

File ~/repos/pennylane/pennylane/devices/default_qubit.py:476, in DefaultQubit.supports_derivatives(self, execution_config, circuit)
    471     return not circuit.shots and not any(
    472         isinstance(m.obs, qml.SparseHamiltonian) for m in circuit.measurements
    473     )
    475 if execution_config.gradient_method in {"adjoint", "best"}:
--> 476     [HIDDEN]
    477 return False

File ~/repos/pennylane/pennylane/devices/default_qubit.py:196, in _supports_adjoint(circuit, device_wires, device_name)
    193 _add_adjoint_transforms(prog)
    195 try:
--> 196     prog((circuit,))
    197 except (qml.operation.DecompositionUndefinedError, qml.DeviceError, AttributeError):
    198     return False

File ~/repos/pennylane/pennylane/transforms/core/transform_program.py:509, in TransformProgram.__call__(self, tapes)
    507 if self._argnums is not None and self._argnums[i] is not None:
    508     tape.trainable_params = self._argnums[i][j]
--> 509 new_tapes, fn = transform(tape, *targs, **tkwargs)
    510 execution_tapes.extend(new_tapes)
    512 fns.append(fn)

File ~/repos/pennylane/pennylane/devices/default_qubit.py:166, in [HIDDEN](tape, device_vjp)
    164 complex_data = [qml.math.cast(p, complex) for p in params]
    165 tape = tape.bind_new_parameters(complex_data, list(range(len(params))))
--> 166 [HIDDEN]
    167 state_tape = qml.tape.QuantumScript(tape.operations, [new_mp])
    168 return (state_tape,), partial(
    169     all_state_postprocessing, measurements=tape.measurements, wire_order=tape.wires
    170 )

File ~/repos/pennylane/pennylane/measurements/state.py:140, in StateMP.__init__(self, wires, id)
    139 def __init__(self, wires: Optional[Wires] = None, id: Optional[str] = None):
--> 140     super().__init__(wires=wires, id=id)

File ~/repos/pennylane/pennylane/measurements/measurements.py:177, in MeasurementProcess.__init__(self, obs, wires, eigvals, id)
    175 if wires is not None:
    176     if len(wires) == 0:
--> 177         raise ValueError("Cannot set an empty list of wires.")
    178     if obs is not None:
    179         raise ValueError("Cannot set the wires if an observable is provided.")

ValueError: Cannot set an empty list of wires.
```


### System information

```shell
pl dev
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.

### Additional contract requirements

- During adjoint-support validation, measurements whose scope is all device wires must be interpreted using the device's wires, matching forward execution, even when the differentiated tape has no wires of its own.
- A two-wire `default.qubit` QNode with `diff_method="adjoint"` that returns `qml.state()` must not raise an error during validation.
