[Bug] qml.equal return False unexpectedly
Encountered this problem in https://github.com/PennyLaneAI/pennylane/pull/5051 for creating a `qml.commutator` function.

Even though the result from computing the commutator seems the same, `qml.equal` returns `False` when checking with the true result. Really not clear what the problem is here 🤔

```
H1 = qml.prod(qml.PauliX(0), qml.PauliX(1))
H2 = qml.s_prod(1., qml.sum(qml.PauliY(0), qml.PauliY(1)))
true_res = qml.sum(qml.s_prod(2j, qml.PauliZ(0) @ qml.PauliX(1)), qml.s_prod(2j, qml.PauliX(0) @ qml.PauliZ(1)))
res = qml.prod(H1, H2) - qml.prod(H2, H1)
res = res.simplify()
res = res.simplify()

>>> true_res, res
((2j*(PauliZ(wires=[0]) @ PauliX(wires=[1]))) + (2j*(PauliX(wires=[0]) @ PauliZ(wires=[1]))),
 (2j*(PauliZ(wires=[0]) @ PauliX(wires=[1]))) + (2j*(PauliX(wires=[0]) @ PauliZ(wires=[1]))))
>>> qml.equal(true_res, res)
False
>>> type(true_res), type(res)
(pennylane.ops.op_math.sum.Sum, pennylane.ops.op_math.sum.Sum)
```

The same happens when using legacy classes (Tensor, Hamiltonian), the operators are still identical though the ordering of some of the operators changes:

```
H1 = qml.Hamiltonian([1.], [qml.PauliX(0) @ qml.PauliX(1)])
H2 = qml.Hamiltonian([1.], [qml.PauliY(0) + qml.PauliY(1)])
true_res = qml.sum(qml.s_prod(2j, qml.PauliZ(0) @ qml.PauliX(1)), qml.s_prod(2j, qml.PauliX(0) @ qml.PauliZ(1)))
res = qml.prod(H1, H2) - qml.prod(H2, H1)
res = res.simplify()
res = res.simplify()

>>> true_res, res # order of operators changes but that should _not_ be an issue for qml.equal
((2j*(PauliZ(wires=[0]) @ PauliX(wires=[1]))) + (2j*(PauliX(wires=[0]) @ PauliZ(wires=[1]))),
 (2j*(PauliX(wires=[1]) @ PauliZ(wires=[0]))) + (2j*(PauliZ(wires=[1]) @ PauliX(wires=[0]))))
>>> qml.equal(true_res, res)
False
>>> type(true_res), type(res)
(pennylane.ops.op_math.sum.Sum, pennylane.ops.op_math.sum.Sum)
```

I tried on the branch of this [bug fix](https://github.com/PennyLaneAI/pennylane/pull/5037), without success. I think this is a separate issue.
