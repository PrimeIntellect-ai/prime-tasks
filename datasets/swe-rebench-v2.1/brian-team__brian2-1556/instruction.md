Confusing VariableView behavior: reports shape of parent Quantity
I expect to be able to use VariableView like a Quantity, but I get some surprising behavior where `shape` reflects the parent `Group` object. `len()` is not affected

```python
import brian2.only as b2
ng = b2.NeuronGroup(10, 'v : 1')

print(ng[:5].v)
# <neurongroup_subgroup.v: array([0., 0., 0., 0., 0.])>

print(len(ng[:5].v))
# 5

# 🚨 the weird part 🚨
print(ng[:5].v.shape)
# (10,)

# this works as expected, but it's a new `Quantity` as opposed to a `VariableView`
print(ng.v[:5].shape)
# (5,)
```
