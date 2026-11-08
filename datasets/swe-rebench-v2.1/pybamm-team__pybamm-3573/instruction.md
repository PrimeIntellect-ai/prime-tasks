Introduction of 3 electrode setup
### Description

The feature involves additional potential variables. The first one equates to a potential difference between the current collector of the anode and the middle of separator called "Negative electrode potential vs separator reference". The second one is the potential difference between the middle of the separator and the current collector of the positive electrode called "Positive electrode potential vs sparator reference".


### Motivation

Motivation for this comes from the 3-electrode setup in the lab.

In a 2-electrode setup in the lab one can not resolve the individual SOCs of each electrode. You only get the potential difference between both current collectors. In a 3-electrode setup a reference electrode is introduced in the middle of the separator for example a little place of lithium or a whole lithium reference ring around the separator. With the reference electrode, the potentials of both electrodes can be monitored separately. These potentials can for example be used for plating detection on lithium ion graphite anodes.

Modelling this feature directly in PyBaMM is not yet possible. There are already a lot of fancy ways in pybamm to resolve processes on the electrodes directly for example different overpotential contributions. These though can not be compared directly to measured data in the lab. With the mentioned feature there is a way to describe these electrode potentials in PyBaMM and relate them directly to measured potentials in the lab.  The additional potential variables could help a great deal for fitting models better to measurements and increase model validity.


### Possible Implementation

As a rough draft for my own simulations i implemented the following lines in "base_electrolyte_conductivity". It could be placed in the current-collector submodel or maybe also "base electrode" but since the separator electrolyte potential is needed this would involve including a new submodel at these places. For now these lines worked for me:

```
[HIDDEN]
```
There is one caveat though. For a point of reference we need a single value (here termed "phi_e_s_mid"). Typically this would just be the evaluation of the electrolyte in the middle of the separator but until now i did not manage to get it working. I tried to do it with `phi_e_s.evaluate(param.L_n+param.L_s/2)' but it didn't want to be evaluated as it said the method "evaluate is not impleted for "Current function"'. I did not try it with another approach as this wouldn't be working for my system.




### Additional context

Provided there is feedback and discussion and it's not too much work to put the feature inside while making sure that everything else in the code still works i would implement this and create a pull request.

### Additional contract requirements

- Add a public unary operator `pybamm.EvaluateAt(child, position)` to the expression tree. `child` is the symbol to evaluate and `position` is the point in space at which to evaluate it. The supplied position is available through the public attribute `position`.
- The Jacobian of `pybamm.EvaluateAt` with respect to any variable is `pybamm.Scalar(0)`.
- Add a public method `insert_reference_electrode(position=None)` to lithium-ion models in `pybamm.lithium_ion`. It adds the variables "Reference electrode potential [V]", "Positive electrode 3E potential [V]" and, when the working electrode is "both", "Negative electrode 3E potential [V]". The reference electrode potential is the electrolyte potential evaluated at `position`; when `position` is `None` the separator midpoint is used. It raises `NotImplementedError` when the model's `dimensionality` option is not 0, with a message containing the phrase `Reference electrode can only be`.
- Add a public method `evaluate_at(symbol, discretised_child, position)` to spatial methods. The base `pybamm.SpatialMethod` implementation raises `NotImplementedError`. The `pybamm.FiniteVolume` implementation returns a `pybamm.MatrixMultiplication` whose value is the discretised child evaluated at the mesh node closest to `position`.
- `pybamm.ParameterValues.process_symbol` processes the `position` of a `pybamm.EvaluateAt` and raises `ValueError` with a message containing `'position' in 'EvaluateAt'` when the processed position is not a `pybamm.Scalar`.
