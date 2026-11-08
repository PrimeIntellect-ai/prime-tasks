[BUG] `draw_mpl` is not fully compatible with work wires
### Expected behavior

A circuit can be drawn even if the operators contain work wires (that are not to be drawn!)

### Actual behavior

Mapping around wires fails in `draw_mpl` if there are work wires present that get overwritten.


### Additional information

This is quite similar to #7580 , fixed in #7581 .

### Source code

```shell
import pennylane as qml


dev = qml.device("default.qubit")
@qml.qnode(dev)
def circuit():

    qml.ctrl(qml.CRZ(0.5, [0, 2]), control=[3], work_wires=[1])
    return qml.probs(wires=[3])

qml.draw_mpl(circuit)()
```

### Tracebacks

```shell
---------------------------------------------------------------------------
ValueError                                Traceback (most recent call last)
Cell In[5], line 11
      8     qml.ctrl(qml.CRZ(0.5, [0, 2]), control=[3], work_wires=[1])
      9     return qml.probs(wires=[3])
---> 11 qml.draw_mpl(circuit)()

File ~/repos/pennylane/pennylane/drawer/draw.py:858, in _draw_mpl_qnode.<locals>.wrapper(*args, **kwargs_qnode)
    855     except TypeError:
    856         _wire_order = tape.wires
--> 858 return tape_mpl(
    859     tape,
    860     wire_order=_wire_order,
    861     show_all_wires=show_all_wires,
    862     decimals=decimals,
    863     style=style,
    864     fig=fig,
    865     **kwargs,
    866 )

File ~/repos/pennylane/pennylane/drawer/tape_mpl.py:545, in tape_mpl(tape, wire_order, show_all_wires, decimals, style, fig, max_length, **kwargs)
    542     _set_style(style)
    544 try:
--> 545     return _tape_mpl(
    546         tape,
    547         wire_order=wire_order,
    548         show_all_wires=show_all_wires,
    549         decimals=decimals,
    550         fig=fig,
    551         max_length=max_length,
    552         **kwargs,
    553     )
    554 finally:
    555     if update_style:
    556         # we don't want to mess with how it modifies whether the interface is interactive
    557         # but we want to restore everything else

File ~/repos/pennylane/pennylane/drawer/tape_mpl.py:294, in _tape_mpl(tape, wire_order, show_all_wires, max_length, **kwargs)
    292 wire_map = convert_wire_order(tape, wire_order=wire_order, show_all_wires=show_all_wires)
    293 tape = transform_deferred_measurements_tape(tape)
--> 294 tape = ops.functions.map_wires(tape, wire_map=wire_map)[0][0]
    295 bit_map = default_bit_map(tape)
    297 layers = drawable_layers(tape.operations, wire_map={i: i for i in tape.wires}, bit_map=bit_map)

File ~/repos/pennylane/pennylane/ops/functions/map_wires.py:229, in map_wires(input, wire_map, queue, replace)
    227         return new_op
    228     return input.map_wires(wire_map=wire_map)
--> 229 return _map_wires_transform(input, wire_map=wire_map, queue=queue)

File ~/repos/pennylane/pennylane/transforms/core/transform_dispatcher.py:254, in TransformDispatcher.__call__(self, *targs, **tkwargs)
    251         return expand_processing(processed_results)
    253 else:
--> 254     transformed_tapes, processing_fn = self._transform(obj, *targs, **tkwargs)
    256 if self.is_informative:
    257     return processing_fn(transformed_tapes)

File ~/repos/pennylane/pennylane/ops/functions/map_wires.py:241, in _map_wires_transform(tape, wire_map, queue)
    237 @partial(transform, plxpr_transform=map_wires_plxpr_to_plxpr)
    238 def _map_wires_transform(
    239     tape: QuantumScript, wire_map=None, queue=False
    240 ) -> tuple[QuantumScriptBatch, PostprocessingFn]:
--> 241     ops = [
    242         (
    243             map_wires(op, wire_map, queue=queue)
    244             if not isinstance(op, QuantumScript)
    245             else map_wires(op, wire_map, queue=queue)[0][0]
    246         )
    247         for op in tape.operations
    248     ]
    249     measurements = [map_wires(m, wire_map, queue=queue) for m in tape.measurements]
    251     out = tape.__class__(
    252         ops=ops, measurements=measurements, shots=tape.shots, trainable_params=tape.trainable_params
    253     )

File ~/repos/pennylane/pennylane/ops/functions/map_wires.py:243, in <listcomp>(.0)
    237 @partial(transform, plxpr_transform=map_wires_plxpr_to_plxpr)
    238 def _map_wires_transform(
    239     tape: QuantumScript, wire_map=None, queue=False
    240 ) -> tuple[QuantumScriptBatch, PostprocessingFn]:
    241     ops = [
    242         (
--> 243             map_wires(op, wire_map, queue=queue)
    244             if not isinstance(op, QuantumScript)
    245             else map_wires(op, wire_map, queue=queue)[0][0]
    246         )
    247         for op in tape.operations
    248     ]
    249     measurements = [map_wires(m, wire_map, queue=queue) for m in tape.measurements]
    251     out = tape.__class__(
    252         ops=ops, measurements=measurements, shots=tape.shots, trainable_params=tape.trainable_params
    253     )

File ~/repos/pennylane/pennylane/ops/functions/map_wires.py:228, in map_wires(input, wire_map, queue, replace)
    226             qml.apply(new_op)
    227         return new_op
--> 228     return input.map_wires(wire_map=wire_map)
    229 return _map_wires_transform(input, wire_map=wire_map, queue=queue)

File ~/repos/pennylane/pennylane/ops/op_math/controlled.py:699, in Controlled.map_wires(self, wire_map)
    696 new_control_wires = Wires([wire_map.get(wire, wire) for wire in self.control_wires])
    697 new_work_wires = Wires([wire_map.get(wire, wire) for wire in self.work_wires])
--> 699 return ctrl(
    700     op=new_base,
    701     control=new_control_wires,
    702     control_values=self.control_values,
    703     work_wires=new_work_wires,
    704 )

File ~/repos/pennylane/pennylane/ops/op_math/controlled.py:169, in ctrl(op, control, control_values, work_wires, work_wire_type)
    161 if math.is_abstract(op):
    162     return Controlled(
    163         op,
    164         control,
   (...)
    167         work_wire_type=work_wire_type,
    168     )
--> 169 return create_controlled_op(
    170     op,
    171     control,
    172     control_values=control_values,
    173     work_wires=work_wires,
    174     work_wire_type=work_wire_type,
    175 )

File ~/repos/pennylane/pennylane/ops/op_math/controlled.py:229, in create_controlled_op(op, control, control_values, work_wires, work_wire_type)
    220     return ctrl(
    221         op.base,
    222         control=control + op.control_wires,
   (...)
    225         work_wire_type=work_wire_type,
    226     )
    228 if isinstance(op, Operator):
--> 229     return Controlled(
    230         op,
    231         control_wires=control,
    232         control_values=control_values,
    233         work_wires=work_wires,
    234         work_wire_type=work_wire_type,
    235     )
    237 if not callable(op):
    238     raise ValueError(
    239         f"The object {op} of type {type(op)} is not an Operator or callable. "
    240         "This error might occur if you apply ctrl to a list "
    241         "of operations instead of a function or Operator."
    242     )

File ~/repos/pennylane/pennylane/capture/capture_meta.py:30, in _stop_autograph.<locals>.new_f(*args, **kwargs)
     29 def new_f(*args, **kwargs):
---> 30     return f(*args, **kwargs)

File ~/repos/pennylane/pennylane/capture/capture_meta.py:97, in CaptureMeta.__call__(cls, *args, **kwargs)
     93 if enabled():
     94     # when tracing is enabled, we want to
     95     # use bind to construct the class if we want class construction to add it to the jaxpr
     96     return cls._primitive_bind_call(*args, **kwargs)
---> 97 return type.__call__(cls, *args, **kwargs)

File ~/repos/pennylane/pennylane/ops/op_math/controlled.py:1048, in ControlledOp.__init__(self, base, control_wires, control_values, work_wires, work_wire_type, id)
   1039 def __init__(
   1040     self,
   1041     base,
   (...)
   1046     id=None,
   1047 ):
-> 1048     super().__init__(base, control_wires, control_values, work_wires, work_wire_type, id)
   1049     # check the grad_recipe validity
   1050     if self.grad_recipe is None:
   1051         # Make sure grad_recipe is an iterable of correct length instead of None

File ~/repos/pennylane/pennylane/ops/op_math/controlled.py:597, in Controlled.__init__(self, base, control_wires, control_values, work_wires, work_wire_type, id)
    594     raise ValueError("The control wires must be different from the base operation wires.")
    596 if len(Wires.shared_wires([work_wires, base.wires + control_wires])) != 0:
--> 597     raise ValueError(
    598         "Work wires must be different the control_wires and base operation wires."
    599     )
    601 if work_wire_type not in {"clean", "dirty"}:
    602     raise ValueError(
    603         f"work_wire_type must be either 'clean' or 'dirty'. Got '{work_wire_type}'."
    604     )

ValueError: Work wires must be different the control_wires and base operation wires.
```

### System information

```shell
pl dev
```

### Existing GitHub issues

- [x] I have searched existing GitHub issues to make sure the issue does not already exist.

### Additional contract requirements

- `default_wire_map(tape)` in `pennylane/drawer/utils.py` returns a tuple of two dictionaries `(full_wire_map, used_wire_map)`. `full_wire_map` maps every wire that appears in the tape (operational wires and work wires) to consecutive non-negative integers in order of appearance, with work-only wires appended after the used wires. `used_wire_map` maps only the wires used by the operations, excluding work-only wires.
- `convert_wire_order(tape, wire_order=None, show_all_wires=False)` in `pennylane/drawer/utils.py` returns a tuple of two dictionaries `(full_wire_map, used_wire_map)` mapping wires to consecutive non-negative integers in the resolved order. `full_wire_map` includes all wires (including work wires); `used_wire_map` excludes work-only wires unless `show_all_wires=True`.
