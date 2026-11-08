More informative QNode `diff_method`
Currently, QNode's have an attribute `diff_method` that captures the user-provided `diff_method` keyword or the default `"best"`.

If `diff_method=="best"`, then the class will determine which differentiation method to use based on a combination of various things like device and interface.

But the attribute `diff_method` is not updated with this choice. To find which method actually got used, we need to query `qnode.qtape.jacobian_options['method']`, which is unnecessarily complicated for a fairly central piece of information.

Example:

```python
dev = qml.device('default.qubit', wires=2)

@qml.qnode(dev)
def circ(x):
    qml.RX(x, wires=0)
    return qml.expval(qml.PauliZ(0))

print(circ.diff_method)
circ(0.1)
print(circ.qtape.jacobian_options['method'] )
```

```
best
backprop
```

I propose we update `QNode.diff_method` once a differentiation method is chosen.

----

*List of tasks for completion:*

1. Update the logic of the QNode such that the `diff_method` attribute is updated after tape construction, once the `QNode.qtape.jacobian_options['method']` information is available;
2. Add unit and integration tests that test the new functionality and check multiple differentiation methods.
