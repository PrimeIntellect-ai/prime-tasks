[BUG] Hamiltonian expansion with dynamic shots fails
### Expected behavior

I expect that a Hamiltonian expectation value is expanded if the execution occurs with finite shots.

### Actual behavior

If the device has `shots=None` upon construction, but the circuit is dynamically executed with finite shots, Hamiltonian expansion does not occur.

[HIDDEN]

### Additional information

_No response_

### Source code

```shell
@qml.qnode(qml.device('default.qubit', wires=2), diff_method=None)
def circuit():
    return qml.expval(2.0 * qml.PauliX(0))

circuit(shots=20)
```


### Tracebacks

```shell
---------------------------------------------------------------------------
AssertionError                            Traceback (most recent call last)
Cell In [4], line 1
----> 1 circuit(shots=20)

File ~/Prog/pennylane/pennylane/qnode.py:665, in QNode.__call__(self, *args, **kwargs)
    661     self._update_original_device()
    663     return res
--> 665 res = qml.execute(
    666     [self.tape],
    667     device=self.device,
    668     gradient_fn=self.gradient_fn,
    669     interface=self.interface,
    670     gradient_kwargs=self.gradient_kwargs,
    671     override_shots=override_shots,
    672     **self.execute_kwargs,
    673 )
    675 if old_interface == "auto":
    676     self.interface = "auto"

File ~/Prog/pennylane/pennylane/interfaces/execution.py:637, in execute(tapes, device, gradient_fn, interface, mode, gradient_kwargs, cache, cachesize, max_diff, override_shots, expand_fn, max_expansion, device_batch_transform)
    631         return batch_fn(
    632             qml.interfaces.cache_execute(
    633                 batch_execute, cache, return_tuple=False, expand_fn=expand_fn
    634             )(tapes)
    635         )
    636     with qml.tape.Unwrap(*tapes):
--> 637         res = qml.interfaces.cache_execute(
    638             batch_execute, cache, return_tuple=False, expand_fn=expand_fn
    639         )(tapes)
    641     return batch_fn(res)
    643 if gradient_fn == "backprop" or interface is None:

File ~/Prog/pennylane/pennylane/interfaces/execution.py:206, in cache_execute.<locals>.wrapper(tapes, **kwargs)
    202         return (res, []) if return_tuple else res
    204 else:
    205     # execute all unique tapes that do not exist in the cache
--> 206     res = fn(execution_tapes.values(), **kwargs)
    208 final_res = []
    210 for i, tape in enumerate(tapes):

File ~/Prog/pennylane/pennylane/interfaces/execution.py:131, in cache_execute.<locals>.fn(tapes, **kwargs)
    129 def fn(tapes: Sequence[QuantumTape], **kwargs):  # pylint: disable=function-redefined
    130     tapes = [expand_fn(tape) for tape in tapes]
--> 131     return original_fn(tapes, **kwargs)

File /Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/lib/python3.9/contextlib.py:79, in ContextDecorator.__call__.<locals>.inner(*args, **kwds)
     76 @wraps(func)
     77 def inner(*args, **kwds):
     78     with self._recreate_cm():
---> 79         return func(*args, **kwds)

File ~/Prog/pennylane/pennylane/_qubit_device.py:624, in QubitDevice.batch_execute(self, circuits)
    621     self.reset()
    623     # TODO: Insert control on value here
--> 624     res = self.execute(circuit)
    625     results.append(res)
    627 if self.tracker.active:

File ~/Prog/pennylane/pennylane/_qubit_device.py:390, in QubitDevice.execute(self, circuit, **kwargs)
    388     results = self._collect_shotvector_results(circuit, counts_exist)
    389 else:
--> 390     results = self.statistics(circuit.observables, circuit=circuit)
    392 if not circuit.is_sampled:
    394     if len(circuit.measurements) == 1:

File ~/Prog/pennylane/pennylane/_qubit_device.py:743, in QubitDevice.statistics(self, observables, shot_range, bin_size, circuit)
    739 for obs in observables:
    740     # Pass instances directly
    741     if obs.return_type is Expectation:
    742         # Appends a result of shape (num_bins,) if bin_size is not None, else a scalar
--> 743         results.append(self.expval(obs, shot_range=shot_range, bin_size=bin_size))
    745     elif obs.return_type is Variance:
    746         # Appends a result of shape (num_bins,) if bin_size is not None, else a scalar
    747         results.append(self.var(obs, shot_range=shot_range, bin_size=bin_size))

File ~/Prog/pennylane/pennylane/devices/default_qubit.py:534, in DefaultQubit.expval(self, observable, shot_range, bin_size)
    530 # intercept other Hamiltonians
    531 # TODO: Ideally, this logic should not live in the Device, but be moved
    532 # to a component that can be re-used by devices as needed.
    533 if observable.name in ("Hamiltonian", "SparseHamiltonian"):
--> 534     assert self.shots is None, f"{observable.name} must be used with shots=None"
    536     self.map_wires(observable.wires)
    537     backprop_mode = (
    538         not isinstance(self.state, np.ndarray)
    539         or any(not isinstance(d, (float, np.ndarray)) for d in observable.data)
    540     ) and observable.name == "Hamiltonian"

AssertionError: Hamiltonian must be used with shots=None
```


### System information

```shell
On master.
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.

### Additional contract requirements

- A Hamiltonian expectation value must be expanded when execution uses finite shots, including when the device was constructed with `shots=None` and the finite shot count is supplied dynamically for that execution.
