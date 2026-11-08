Add a `work_wires` attribute to `GroverOperator`
### Feature details

Add an attribute to `GroverOperator` that outputs its `work_wires`. Similar to `MultiControlledX`:

```
🍞 op = qml.MultiControlledX(wires=[0, 1, 2 ,3], work_wires=[4, 5])
🍞 op.work_wires
Wires([4, 5])
```

### Implementation

🦗

### How important would you say this feature is?

1: Not important. Would be nice to have.

### Additional information

_No response_
