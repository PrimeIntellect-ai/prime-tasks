support a nice way of changing the learning rate
It would be nice to have a easy and rule independent way of changing the learning rate like in Flux.jl.

Right now the best way i can think of is making another state tuple while changing the first argument but then changing the learning rate is not rule independent.

@mcabbott  suggested
> Although perhaps there ought to be one, like `st = setup(rule, st)` without zero-ing the momenta. Maybe make an issue?

related: #15 (seems to be not active)

### Additional contract requirements

Provide the public operation `Optimisers.adjust(tree, η::Real)` to change the learning rate throughout an optimizer state tree. The operation must preserve the optimizer's already accumulated momentum and other training state, so continued updates use that existing state with the new learning rate.
