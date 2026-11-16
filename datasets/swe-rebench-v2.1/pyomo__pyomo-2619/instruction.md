Scaling transformations on Block structured models
I have been working with the Pyomo scaling transformation in preparation for implementing this within IDAES, and I have run into some unexpected behaviour when working with block-structured models. It appears that only scaling factors declared at the top level of the model are considered by the scaling transformation, and that it does not descend into the block tree to look for additional scaling factors.

I have tested a few cases to try to work out what was happening.

Case 1:

```
import pyomo.environ as pe

###
# create the original unscaled model
###
model = pe.ConcreteModel()

model.b = pe.Block()
model.b.a = pe.Var(initialize=10, bounds=(0,20))

###
# set the scaling parameters
###
model.b.scaling_factor = pe.Suffix(direction=pe.Suffix.EXPORT)
model.b.scaling_factor[model.b.a] = 10

###
# build and solve the scaled model
###
scaled_model = pe.TransformationFactory('core.scale_model').create_using(model)
```

Returns:
`ValueError: ScaleModel transformation called with scaling_method='user', but cannot find the suffix 'scaling_factor' on the model`

This is possibly expected behaviour, but without the `scaling_factor` suffix present at the top level, the transformation returns an error. I do find it strange that the error is a `ValueError` - I would generally expect an `AttributeError` in the case where the attribute was missing completely.

Case 2:

```
import pyomo.environ as pe

###
# create the original unscaled model
###
model = pe.ConcreteModel()

model.b = pe.Block()
model.b.a = pe.Var(initialize=10, bounds=(0,20))

###
# set the scaling parameters
###
model.scaling_factor = pe.Suffix(direction=pe.Suffix.EXPORT)
model.b.scaling_factor = pe.Suffix(direction=pe.Suffix.EXPORT)
model.b.scaling_factor[model.b.a] = 10

###
# build and solve the scaled model
###
scaled_model = pe.TransformationFactory('core.scale_model').create_using(model)

# print the scaled model
scaled_model.b.scaled_a.pprint()
```

Returns:
```
scaled_a : Size=1, Index=None
    Key  : Lower : Value : Upper : Fixed : Stale : Domain
    None :   0.0 :  10.0 :  20.0 : False : False :  Reals
```

The model has been transformed, and the variable `a` replaced by `scaled_a`, but the value and bounds have not been scaled. It appears that the scaling factor(s) defined in child blocks are not being picked up by the transformation.

Case 3:
```
import pyomo.environ as pe

###
# create the original unscaled model
###
model = pe.ConcreteModel()

model.b = pe.Block()
model.b.a = pe.Var(initialize=10, bounds=(0,20))

###
# set the scaling parameters
###
model.scaling_factor = pe.Suffix(direction=pe.Suffix.EXPORT)
model.scaling_factor[model.b.a] = 10

###
# build and solve the scaled model
###
scaled_model = pe.TransformationFactory('core.scale_model').create_using(model)

# print the scaled model
scaled_model.b.scaled_a.pprint()
```

Returns:
```
scaled_a : Size=1, Index=None
    Key  : Lower : Value : Upper : Fixed : Stale : Domain
    None :   0.0 : 100.0 : 200.0 : False : False :  Reals
```

This works now, and the variable value and bounds have been scaled.

It would be good if the scaling transformation would descend into the block structure to look for scaling factors, as it makes more sense to declare these at the same level as the component is declared. This also simplifies modular construction of the scaling factors, as each block can be responsible for its own scaling factors, without having to propagate these up to the top level of the model.

### Additional contract requirements

When a `scaling_factor` suffix is declared on a descendant Block, its entries must be used for components within that Block without being copied to the model-level suffix. Scaling a bounded variable must scale its value and both finite bounds by the applicable factor. A scaling factor declared on the model must also apply to a component nested inside a Block when the suffix entry is keyed by that component.
