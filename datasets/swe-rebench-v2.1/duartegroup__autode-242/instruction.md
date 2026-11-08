Division and multiplication of `autode.values.Value` creates wrong units
**Describe the bug**
<!-- A clear and concise description of what the bug is. -->

Multiplication and division do not generate autode.values with the correct units. As a simple fix multiplication could return a float, given it's (potentially) an uncommon occurrence.

**To Reproduce**
<!-- Steps to reproduce the behaviour: code with output -->


```python
>>> import autode as ade
>>> e = ade.values.PotentialEnergy(1)
>>> e
Energy(1.0 Ha)
>>> e * e
Energy(1.0 Ha)
>>> e / e
Energy(1.0 Ha)
>>> # Addition and subtraction are okay
>>> e + e
Energy(2.0 Ha)
>>> e - e
Energy(0.0 Ha)
```

**Expected behavior**
<!-- A clear and concise description of what you expected to happen. -->

Division results in no units and multiplication Ha^2

**Environment**
<!-- please complete the following information. -->
 - autodE version: 1.3.4

### Additional contract requirements

Dividing one `Value` by another must return a unitless numeric result. Multiplying two `Value` instances must produce the ordinary numeric product without carrying the operands' unchanged units. A unitless numeric result is acceptable instead of a `Value` carrying the combined product units (for example, Ha²). In either operation, the numeric result must be the ordinary quotient or product of the operands.
