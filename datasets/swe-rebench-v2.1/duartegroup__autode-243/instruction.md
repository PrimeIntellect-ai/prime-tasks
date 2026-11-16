Using autodE in Interactive python shell causes unusual change in units
Only seen from interactive python shell.

```python
>>> import autode as ade
>>> mol = ade.Molecule(smiles='CCO')
>>> mol.calc_hessian(method=ade.methods.XTB(),n_cores=6)
>>> mol.hessian.units
Unit(Ha Å^-2)
>>> mol.hessian.   # pressing tab twice to get all visible attributes
mol.hessian.T                  mol.hessian.min(
mol.hessian.all(               mol.hessian.n_tr
mol.hessian.any(               mol.hessian.n_v
mol.hessian.argmax(            mol.hessian.nbytes
mol.hessian.argmin(            mol.hessian.ndim
... # wall of text hidden
>>> mol.hessian.units  # units changed magically from Ha/ang^2 to Joule/ang^2?
Unit(J ang^-2)
```

I have looked at the values in the Hessian and the units really do change. (i.e. the numbers change as well) I am not quite sure why this is happening. But it would be problematic if the units changed randomly in the middle of calculations.

**Environment**
 - Operating System: MacOS 12.6
 - Python version: Python 3.10
 - autodE version: 1.3.4

### Additional contract requirements

Interactive inspection or calculation involving Hessian-derived data must not unexpectedly change the Hessian's unit metadata or numeric values.
