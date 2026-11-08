[BUG] wires initialization issue
### Expected behavior

It would expect the following script to return `True`

`Wires(["a"]) == Wires([Wires("a")])`

i.e. detect if there are nested wires, and not accumulate them as different objects



### Actual behavior

Currently, they are different wires, which generates unwanted situations such as:

![image](https://github.com/user-attachments/assets/e7d7135f-4d65-47d0-a05f-c097f61f259a)


### Additional information

_No response_

### Source code

_No response_

### Tracebacks

_No response_

### System information

```shell
Platform info:           macOS-14.6.1-arm64-arm-64bit
Python version:          3.11.10
Numpy version:           1.26.4
Scipy version:           1.13.0
Installed devices:
- default.clifford (PennyLane-0.40.0.dev27)
- default.gaussian (PennyLane-0.40.0.dev27)
- default.mixed (PennyLane-0.40.0.dev27)
- default.qubit (PennyLane-0.40.0.dev27)
- default.qutrit (PennyLane-0.40.0.dev27)
- default.qutrit.mixed (PennyLane-0.40.0.dev27)
- default.tensor (PennyLane-0.40.0.dev27)
- null.qubit (PennyLane-0.40.0.dev27)
- reference.qubit (PennyLane-0.40.0.dev27)
- lightning.kokkos (PennyLane_Lightning_Kokkos-0.40.0.dev14)
- lightning.qubit (PennyLane_Lightning-0.40.0.dev14)
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.
