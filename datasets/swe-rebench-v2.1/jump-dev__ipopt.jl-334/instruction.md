copy_to does not copy attributes for variable bound constraints
When calling copy_to, at some point MOI.pass_attributes gets called (via MOI.Utilities.default_copy_to()):
```julia
function MOI.copy_to(model::Optimizer, src::MOI.ModelLike)
    return MOI.Utilities.default_copy_to(model, src)
end
```
```julia
function pass_attributes(
    dest::MOI.ModelLike,
    src::MOI.ModelLike,
    index_map::IndexMap,
    cis_src::Vector{MOI.ConstraintIndex{F,S}},
) where {F,S}
    for attr in MOI.get(src, MOI.ListOfConstraintAttributesSet{F,S}())
        [HIDDEN]
        _pass_attribute(dest, src, index_map, cis_src, attr)
    end
    return
end
```
currently, MOI.supports() in this case is defined as follows:
```julia
[HIDDEN]
```
where
```julia
const _SETS =
    Union{MOI.GreaterThan{Float64},MOI.LessThan{Float64},MOI.EqualTo{Float64}}

const _FUNCTIONS = Union{
    MOI.ScalarAffineFunction{Float64},
    MOI.ScalarQuadraticFunction{Float64},
}
```
This results in the fact that attributes for variable bound constraints are not copied, since calling MOI.supports() for bound constraints (where F=MOI.VariableIndex) returns the default false and attributes are not passed using
```julia
 _pass_attribute(dest, src, index_map, cis_src, attr)
```
Extending the MOI.supports definition to variable bounds creates a lot of other problems.
However, things such as ConstraintDualStart have get/set methods that work as desired.
[HIDDEN]
If so, I would be happy to start with a PR at least implementing the dual start values.
In case this is not a good idea, a brief warning about not copying bound dual starting values would maybe be good.
This also relates to the other attributes skipped by the continue statement in pass_attributes(), but I think bound dual starting values are the most relevant (primal starts are defined by variable primal starts, and copying names for bounds is also not really relevant...).

### Additional contract requirements

- When `copy_to` copies a model, transfer each set `ConstraintDualStart` value for a variable-bound constraint to its corresponding destination constraint.
