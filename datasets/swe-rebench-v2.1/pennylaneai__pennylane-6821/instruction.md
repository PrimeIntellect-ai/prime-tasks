Allow specifying `basis_set` as an empty set to `qml.compile`
We currently have a `basis_set` keyword argument to `qml.compile` that specifies which operations to not decompose.  If an operation is not in the basis set and does not have a decomposition, we leave it be.

We may sometimes want to decompose anything that can potentially be decomposed:

```
@partial(qml.compile, basis_set={})
@qml.qnode(qml.device('default.qubit'))
def circuit():
    qml.U2(0.5, 0.6, 0)
    return qml.expval(qml.Z(0))
```

The above syntax should indicate "as long as it has a decomposition, decompose it".

Right now we interpret `{}` as Falsy, and change the basis set to `qml.ops.__all__`. Instead, we should interpret `{}`, `()`, and `[]` (any non-`None`) object, as an actual basis set. An empty basis set should be a valid basis set.
