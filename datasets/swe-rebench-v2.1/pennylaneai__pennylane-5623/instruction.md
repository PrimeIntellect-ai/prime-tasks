[BUG] `param_shift` with `broadcast=True` does not work with zero-length recipes
### Expected behavior

`param_shift` has feature parity between `broadcast=True` and `broadcast=False`

### Actual behavior

The (somewhat esoteric) example from the test suite below runs with `broadcast=False` but not with `broadcast=True`.

### Additional information

If we do not include the commented `assert` line, the gradient computation will raise an error, because the created tapes are not valid.

If we include the commented `assert` line in the code below, we see that too many tapes are being created when `broadcast=True`. This is because unnecessary tapes with `batch_size=0` are being created, which is the core bug making the tapes invalid.



### Source code

```shell
ops_with_custom_recipe = [1]
broadcast = True

dev = qml.device("default.qubit", wires=2)
x = [0.543, -0.654]

with qml.queuing.AnnotatedQueue() as q:
    qml.RX(x[0], wires=[0])
    qml.RX(x[1], wires=[0])
    qml.expval(qml.PauliZ(0))

tape = qml.tape.QuantumScript.from_queue(q)
gradient_recipes = tuple(
    [[-1e7, 1, 0], [1e7, 1, 0]] if i in ops_with_custom_recipe else None for i in range(2)
)
tapes, fn = qml.gradients.param_shift(tape, gradient_recipes=gradient_recipes, broadcast=broadcast)
num_ops_standard = (2 - len(ops_with_custom_recipe))
# assert len(tapes) == (1 if broadcast else 2) * num_ops_standard + (tape.num_params != num_ops_standard)
grad = fn(qml.execute(tapes, dev, None))
print(grad)
```


### Tracebacks

```shell
---------------------------------------------------------------------------
ValueError                                Traceback (most recent call last)
Cell In[2], line 19
     17 num_ops_standard = (2 - len(ops_with_custom_recipe))
     18 # assert len(tapes) == (1 if broadcast else 2) * num_ops_standard + (tape.num_params != num_ops_standard)
---> 19 grad = fn(qml.execute(tapes, dev, None))
     20 print(grad)

File ~/repos/pennylane/pennylane/workflow/execution.py:616, in execute(tapes, device, gradient_fn, interface, transform_program, config, grad_on_execution, gradient_kwargs, cache, cachesize, max_diff, override_shots, expand_fn, max_expansion, device_batch_transform, device_vjp)
    614 # Exiting early if we do not need to deal with an interface boundary
    615 if no_interface_boundary_required:
--> 616     results = inner_execute(tapes)
    617     return post_processing(results)
    619 _grad_on_execution = False

File ~/repos/pennylane/pennylane/workflow/execution.py:297, in _make_inner_execute.<locals>.inner_execute(tapes, **_)
    294 transformed_tapes, transform_post_processing = transform_program(tapes)
    296 if transformed_tapes:
--> 297     results = device_execution(transformed_tapes)
    298 else:
    299     results = ()

File ~/repos/pennylane/pennylane/devices/modifiers/simulator_tracking.py:30, in _track_execute.<locals>.execute(self, circuits, execution_config)
     28 @wraps(untracked_execute)
     29 def execute(self, circuits, execution_config=DefaultExecutionConfig):
---> 30     results = untracked_execute(self, circuits, execution_config)
     31     if isinstance(circuits, QuantumScript):
     32         batch = (circuits,)

File ~/repos/pennylane/pennylane/devices/modifiers/single_tape_support.py:32, in _make_execute.<locals>.execute(self, circuits, execution_config)
     30     is_single_circuit = True
     31     circuits = (circuits,)
---> 32 results = batch_execute(self, circuits, execution_config)
     33 return results[0] if is_single_circuit else results

File ~/repos/pennylane/pennylane/devices/default_qubit.py:594, in DefaultQubit.execute(self, circuits, execution_config)
    591 prng_keys = [self.get_prng_keys()[0] for _ in range(len(circuits))]
    593 if max_workers is None:
--> 594     return tuple(
    595         _simulate_wrapper(
    596             c,
    597             {
    598                 "rng": self._rng,
    599                 "debugger": self._debugger,
    600                 "interface": interface,
    601                 "state_cache": self._state_cache,
    602                 "prng_key": _key,
    603             },
    604         )
    605         for c, _key in zip(circuits, prng_keys)
    606     )
    608 vanilla_circuits = [convert_to_numpy_parameters(c) for c in circuits]
    609 seeds = self._rng.integers(2**31 - 1, size=len(vanilla_circuits))

File ~/repos/pennylane/pennylane/devices/default_qubit.py:595, in <genexpr>(.0)
    591 prng_keys = [self.get_prng_keys()[0] for _ in range(len(circuits))]
    593 if max_workers is None:
    594     return tuple(
--> 595         _simulate_wrapper(
    596             c,
    597             {
    598                 "rng": self._rng,
    599                 "debugger": self._debugger,
    600                 "interface": interface,
    601                 "state_cache": self._state_cache,
    602                 "prng_key": _key,
    603             },
    604         )
    605         for c, _key in zip(circuits, prng_keys)
    606     )
    608 vanilla_circuits = [convert_to_numpy_parameters(c) for c in circuits]
    609 seeds = self._rng.integers(2**31 - 1, size=len(vanilla_circuits))

File ~/repos/pennylane/pennylane/devices/default_qubit.py:842, in _simulate_wrapper(circuit, kwargs)
    841 def _simulate_wrapper(circuit, kwargs):
--> 842     return simulate(circuit, **kwargs)

File ~/repos/pennylane/pennylane/devices/qubit/simulate.py:292, in simulate(circuit, debugger, state_cache, **execution_kwargs)
    290 if state_cache is not None:
    291     state_cache[circuit.hash] = state
--> 292 return measure_final_state(circuit, state, is_state_batched, rng=rng, prng_key=meas_key)

File ~/repos/pennylane/pennylane/devices/qubit/simulate.py:213, in measure_final_state(circuit, state, is_state_batched, **execution_kwargs)
    210         raise TypeError("Native mid-circuit measurements are only supported with finite shots.")
    212     if len(circuit.measurements) == 1:
--> 213         return measure(circuit.measurements[0], state, is_state_batched=is_state_batched)
    215     return tuple(
    216         measure(mp, state, is_state_batched=is_state_batched) for mp in circuit.measurements
    217     )
    219 # finite-shot case

File ~/repos/pennylane/pennylane/devices/qubit/measure.py:233, in measure(measurementprocess, state, is_state_batched)
    220 def measure(
    221     measurementprocess: MeasurementProcess, state: TensorLike, is_state_batched: bool = False
    222 ) -> TensorLike:
    223     """Apply a measurement process to a state.
    224
    225     Args:
   (...)
    231         Tensorlike: the result of the measurement
    232     """
--> 233     return get_measurement_function(measurementprocess, state)(
    234         measurementprocess, state, is_state_batched
    235     )

File ~/repos/pennylane/pennylane/devices/qubit/measure.py:72, in state_diagonalizing_gates(measurementprocess, state, is_state_batched)
     70 wires = Wires(range(total_indices))
     71 flattened_state = flatten_state(state, total_indices)
---> 72 return measurementprocess.process_state(flattened_state, wires)

File ~/repos/pennylane/pennylane/measurements/expval.py:142, in ExpectationMP.process_state(self, state, wire_order)
    140     return qml.math.squeeze(self.eigvals())
    141 with qml.queuing.QueuingManager.stop_recording():
--> 142     prob = qml.probs(wires=self.wires).process_state(state=state, wire_order=wire_order)
    143 # In case of broadcasting, `prob` has two axes and this is a matrix-vector product
    144 return self._calculate_expectation(prob)

File ~/repos/pennylane/pennylane/measurements/probs.py:238, in ProbabilityMP.process_state(self, state, wire_order)
    236 prob = qml.math.transpose(prob, desired_axes)
    237 # flatten and return probabilities
--> 238 return qml.math.reshape(prob, flat_shape)

File ~/venvs/dev/lib/python3.10/site-packages/autoray/autoray.py:80, in do(fn, like, *args, **kwargs)
     31 """Do function named ``fn`` on ``(*args, **kwargs)``, peforming single
     32 dispatch to retrieve ``fn`` based on whichever library defines the class of
     33 the ``args[0]``, or the ``like`` keyword argument if specified.
   (...)
     77     <tf.Tensor: id=91, shape=(3, 3), dtype=float32>
     78 """
     79 backend = choose_backend(fn, *args, like=like, **kwargs)
---> 80 return get_lib_fn(backend, fn)(*args, **kwargs)

File ~/venvs/dev/lib/python3.10/site-packages/numpy/core/fromnumeric.py:285, in reshape(a, newshape, order)
    200 @array_function_dispatch(_reshape_dispatcher)
    201 def reshape(a, newshape, order='C'):
    202     """
    203     Gives a new shape to an array without changing its data.
    204
   (...)
    283            [5, 6]])
    284     """
--> 285     return _wrapfunc(a, 'reshape', newshape, order=order)

File ~/venvs/dev/lib/python3.10/site-packages/numpy/core/fromnumeric.py:59, in _wrapfunc(obj, method, *args, **kwds)
     56     return _wrapit(obj, method, *args, **kwds)
     58 try:
---> 59     return bound(*args, **kwds)
     60 except TypeError:
     61     # A TypeError occurs if the object does have such a method in its
     62     # class, but its signature is not identical to that of NumPy's. This
   (...)
     66     # Call _wrapit from within the except clause to ensure a potential
     67     # exception has a traceback chain.
     68     return _wrapit(obj, method, *args, **kwds)

ValueError: cannot reshape array of size 0 into shape (0,newaxis)
```


### System information

```shell
pl dev
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.
