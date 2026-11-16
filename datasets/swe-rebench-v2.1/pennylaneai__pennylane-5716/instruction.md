Issue when using batched data on StronglyEntanglingLayers template.[BUG]
### Expected behavior

I want to use the StronglyEntanglingLayers template to process batched data. the shape of the data is like [batch_size, layers, wires, 3].

### Actual behavior

Some errors happened:
```
.../pennylane/templates/layers/strongly_entangling.py", line 209, in compute_decomposition
    weights[..., l, i, 0],
IndexError: index 10 is out of bounds for dimension 1 with size 10
```

### Additional information

I check the strongly_entangling.py and find this bug may comes from this code:
```
[HIDDEN]
```

the correct code may be

```
201 line:  [HIDDEN]
```

### Source code

_No response_

### Tracebacks

_No response_

### System information

```shell
I run pennylane on the server, and the bug I think is not related to the system.
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.

### Additional contract requirements

- `StronglyEntanglingLayers` must decompose weights shaped `[batch_size, layers, wires, 3]` as batched data, preserving the batch dimension and the corresponding layer and wire parameters in the resulting operations.
