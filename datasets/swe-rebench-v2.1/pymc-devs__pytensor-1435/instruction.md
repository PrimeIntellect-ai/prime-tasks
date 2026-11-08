Vectorize fails on scan
### Description

MRE:

```py

import pytensor
import pytensor.tensor as pt

x = pt.tensor('x', shape=())
out, _ = pytensor.scan(lambda x: x + 1, outputs_info=[x], n_steps=10)
x_vec = pt.tensor('x_vec', shape=(None,))
out_vec = pytensor.graph.vectorize_graph(out, {x:x_vec})

fn = pytensor.function([x_vec], out_vec)
fn([1, 2, 3])
```

Traceback:

<details>

<summary> Full Traceback </summary>

```
TypeError: 'NoneType' object is not subscriptable
Apply node that caused the error: Blockwise{Scan{scan_fn, while_loop=False, inplace=none}, (),(i10)->(o00)}([10], Blockwise{SetSubtensor{:stop}, (i00),(i10),()->(o00)}.0)
Toposort index: 4
Inputs types: [TensorType(int8, shape=(1,)), TensorType(float64, shape=(None, 11))]
Inputs shapes: [(1,), (3, 11)]
Inputs strides: [(1,), (88, 8)]
Inputs values: [array([10], dtype=int8), 'not shown']
Outputs clients: [[Subtensor{:stop, i}(Blockwise{Scan{scan_fn, while_loop=False, inplace=none}, (),(i10)->(o00)}.0, ScalarFromTensor.0, 1)]]

Backtrace when the node is created (use PyTensor flag traceback__limit=N to make it longer):
  File "/home/jesse/mambaforge/envs/pytensor-dev/lib/python3.12/site-packages/IPython/core/async_helpers.py", line 128, in _pseudo_sync_runner
    coro.send(None)
  File "/home/jesse/mambaforge/envs/pytensor-dev/lib/python3.12/site-packages/IPython/core/interactiveshell.py", line 3334, in run_cell_async
    has_raised = await self.run_ast_nodes(code_ast.body, cell_name,
  File "/home/jesse/mambaforge/envs/pytensor-dev/lib/python3.12/site-packages/IPython/core/interactiveshell.py", line 3517, in run_ast_nodes
    if await self.run_code(code, result, async_=asy):
  File "/home/jesse/mambaforge/envs/pytensor-dev/lib/python3.12/site-packages/IPython/core/interactiveshell.py", line 3577, in run_code
    exec(code_obj, self.user_global_ns, self.user_ns)
  File "<ipython-input-21-15ebd24ab700>", line 7, in <module>
    out_vec = pytensor.graph.vectorize_graph(out[0], {x:x_vec})
  File "/mnt/c/Users/Jesse/Python Projects/pytensor/pytensor/graph/replace.py", line 301, in vectorize_graph
    vect_node = vectorize_node(node, *vect_inputs)
  File "/mnt/c/Users/Jesse/Python Projects/pytensor/pytensor/graph/replace.py", line 217, in vectorize_node
    return _vectorize_node(op, node, *batched_inputs)
  File "/home/jesse/mambaforge/envs/pytensor-dev/lib/python3.12/functools.py", line 909, in wrapper
    return dispatch(args[0].__class__)(*args, **kw)

HINT: Use the PyTensor flag `exception_verbosity=high` for a debug print-out and storage map footprint of this Apply node.

In [23]: out_vec.shape.eval()
---------------------------------------------------------------------------
MissingInputError                         Traceback (most recent call last)
Cell In[23], line 1
----> 1 out_vec.shape.eval()

File /mnt/c/Users/Jesse/Python Projects/pytensor/pytensor/graph/basic.py:652, in Variable.eval(self, inputs_to_values, **kwargs)
    649     fn = None
    651 if fn is None:
--> 652     fn = function(inputs, self, **kwargs)
    653     try:
    654         self._fn_cache[cache_key] = fn

File /mnt/c/Users/Jesse/Python Projects/pytensor/pytensor/compile/function/__init__.py:332, in function(inputs, outputs, mode, updates, givens, no_default_updates, accept_inplace, name, rebuild_strict, allow_input_downcast, profile, on_unused_input, trust_input)
    321     fn = orig_function(
    322         inputs,
    323         outputs,
   (...)
    327         trust_input=trust_input,
    328     )
    329 else:
    330     # note: pfunc will also call orig_function -- orig_function is
    331     #      a choke point that all compilation must pass through
--> 332     fn = pfunc(
    333         params=inputs,
    334         outputs=outputs,
    335         mode=mode,
    336         updates=updates,
    337         givens=givens,
    338         no_default_updates=no_default_updates,
    339         accept_inplace=accept_inplace,
    340         name=name,
    341         rebuild_strict=rebuild_strict,
    342         allow_input_downcast=allow_input_downcast,
    343         on_unused_input=on_unused_input,
    344         profile=profile,
    345         output_keys=output_keys,
    346         trust_input=trust_input,
    347     )
    348 return fn

File /mnt/c/Users/Jesse/Python Projects/pytensor/pytensor/compile/function/pfunc.py:466, in pfunc(params, outputs, mode, updates, givens, no_default_updates, accept_inplace, name, rebuild_strict, allow_input_downcast, profile, on_unused_input, output_keys, fgraph, trust_input)
    452     profile = ProfileStats(message=profile)
    454 inputs, cloned_outputs = construct_pfunc_ins_and_outs(
    455     params,
    456     outputs,
   (...)
    463     fgraph=fgraph,
    464 )
--> 466 return orig_function(
    467     inputs,
    468     cloned_outputs,
    469     mode,
    470     accept_inplace=accept_inplace,
    471     name=name,
    472     profile=profile,
    473     on_unused_input=on_unused_input,
    474     output_keys=output_keys,
    475     fgraph=fgraph,
    476     trust_input=trust_input,
    477 )

File /mnt/c/Users/Jesse/Python Projects/pytensor/pytensor/compile/function/types.py:1822, in orig_function(inputs, outputs, mode, accept_inplace, name, profile, on_unused_input, output_keys, fgraph, trust_input)
   1820 try:
   1821     Maker = getattr(mode, "function_maker", FunctionMaker)
-> 1822     m = Maker(
   1823         inputs,
   1824         outputs,
   1825         mode,
   1826         accept_inplace=accept_inplace,
   1827         profile=profile,
   1828         on_unused_input=on_unused_input,
   1829         output_keys=output_keys,
   1830         name=name,
   1831         fgraph=fgraph,
   1832         trust_input=trust_input,
   1833     )
   1834     with config.change_flags(compute_test_value="off"):
   1835         fn = m.create(defaults)

File /mnt/c/Users/Jesse/Python Projects/pytensor/pytensor/compile/function/types.py:1573, in FunctionMaker.__init__(self, inputs, outputs, mode, accept_inplace, function_builder, profile, on_unused_input, fgraph, output_keys, name, no_fgraph_prep, trust_input)
   1569 self.check_unused_inputs(inputs, outputs, on_unused_input)
   1571 indices = [[input, None, [input]] for input in inputs]
-> 1573 fgraph, found_updates = std_fgraph(
   1574     inputs, outputs, accept_inplace, fgraph=fgraph
   1575 )
   1577 if fgraph.profile is None:
   1578     fgraph.profile = profile

File /mnt/c/Users/Jesse/Python Projects/pytensor/pytensor/compile/function/types.py:277, in std_fgraph(input_specs, output_specs, accept_inplace, fgraph, features, force_clone)
    274     input_vars = [spec.variable for spec in input_specs]
    275     clone = force_clone or any(var.owner is not None for var in input_vars)
--> 277     fgraph = FunctionGraph(
    278         input_vars,
    279         [spec.variable for spec in output_specs] + updates,
    280         update_mapping=update_mapping,
    281         clone=clone,
    282     )
    284     found_updates.extend(map(SymbolicOutput, updates))
    286 add_supervisor_to_fgraph(
    287     fgraph=fgraph, input_specs=input_specs, accept_inplace=accept_inplace
    288 )

File /mnt/c/Users/Jesse/Python Projects/pytensor/pytensor/graph/fg.py:164, in FunctionGraph.__init__(self, inputs, outputs, features, clone, update_mapping, **clone_kwds)
    161     self.add_input(in_var, check=False)
    163 for output in outputs:
--> 164     self.add_output(output, reason="init")
    166 self.profile = None
    167 self.update_mapping = update_mapping

File /mnt/c/Users/Jesse/Python Projects/pytensor/pytensor/graph/fg.py:174, in FunctionGraph.add_output(self, var, reason, import_missing)
    172 """Add a new variable as an output to this `FunctionGraph`."""
    173 self.outputs.append(var)
--> 174 self.import_var(var, reason=reason, import_missing=import_missing)
    175 self.clients[var].append((Output(len(self.outputs) - 1).make_node(var), 0))

File /mnt/c/Users/Jesse/Python Projects/pytensor/pytensor/graph/fg.py:323, in FunctionGraph.import_var(self, var, reason, import_missing)
    321 # Imports the owners of the variables
    322 if var.owner and var.owner not in self.apply_nodes:
--> 323     self.import_node(var.owner, reason=reason, import_missing=import_missing)
    324 elif (
    325     var.owner is None
    326     and not isinstance(var, AtomicVariable)
    327     and var not in self.inputs
    328 ):
    329     from pytensor.graph.null_type import NullType

File /mnt/c/Users/Jesse/Python Projects/pytensor/pytensor/graph/fg.py:388, in FunctionGraph.import_node(self, apply_node, check, reason, import_missing)
    379                 else:
    380                     error_msg = (
    381                         f"Input {node.inputs.index(var)} ({var})"
    382                         " of the graph (indices start "
   (...)
    386                         "for more information on this error."
    387                     )
--> 388                     raise MissingInputError(error_msg, variable=var)
    390 for node in new_nodes:
    391     assert node not in self.apply_nodes
```

</details>

The issue appears to be [here](https://github.com/pymc-devs/pytensor/blob/2d414d4129882861b867aaf0d9abcf3135e3d5eb/pytensor/tensor/blockwise.py#L49). [HIDDEN]

### Additional contract requirements

- For the demonstrated recurrent scan, vectorizing its scalar initial-state input to a vector batch must allow execution and produce the corresponding scan output for each batch item. With initial states `[1, 2, 3]` and 10 steps of adding 1, each output sequence should contain the next 10 successive values for its initial state.
