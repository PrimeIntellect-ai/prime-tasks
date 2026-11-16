Result object cannot be printed if a node fails
Consider the following trivial workflow:

```python
@ct.electron(executor="local")
def task():
    raise RuntimeError("error")

@ct.lattice(executor="local")
def workflow():
    return task()
```
I cannot print the result object:
```
dispatch_id = ct.dispatch(workflow)()
result_object = ct.get_result(dispatch_id, wait=True)
print(result_object)
```

```
---------------------------------------------------------------------------
AttributeError                            Traceback (most recent call last)
Input In [18], in <cell line: 11>()
      9 dispatch_id = ct.dispatch(workflow)()
     10 result_object = ct.get_result(dispatch_id, wait=True)
---> 11 print(result_object)

File ~/Agnostiq/code/covalent/covalent/_results_manager/result.py:127, in Result.__str__(self)
    125 node_outputs = self.get_all_node_outputs()
    126 for k, v in node_outputs.items():
--> 127     show_result_str += f"{k}: {v.object_string}\n"
    129 return show_result_str

AttributeError: 'NoneType' object has no attribute 'object_string'
```

This happens because when Covalent encounters an exception when processing a task, the transport graph node's `output` property is set to `None`; for any task that completes normally, the output is a `TransportableObject` (tasks that don't return a value have output `TransportableObject(None)`).

[HIDDEN]

### Additional contract requirements

- Stringifying a result object must not raise when a failed node has a `None` output.
