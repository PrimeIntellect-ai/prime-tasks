Make #729 optional
I understand that #729 is based on a decision to change the SciML style itself, but this has a major impact on everyone using JuliaFormatter with `SciMLStyle`. We use `SciMLStyle` because it mostly fits our style, but we don't want to strictly follow the SciML style (especially not now).

Code that was perfectly readable before
```julia
function interact!(dv, v_particle_system, u_particle_system,
                   v_neighbor_system, u_neighbor_system, neighborhood_search,
                   particle_system::TotalLagrangianSPHSystem,
                   neighbor_system::TotalLagrangianSPHSystem)
    interact_solid_solid!(dv, neighborhood_search, particle_system, neighbor_system)
end
```
suddenly becomes much less readable, where it's not clear where the arguments end and the body begins:
```julia
function interact!(dv, v_particle_system, u_particle_system,
    v_neighbor_system, u_neighbor_system, neighborhood_search,
    particle_system::TotalLagrangianSPHSystem,
    neighbor_system::TotalLagrangianSPHSystem)
    interact_solid_solid!(dv, neighborhood_search, particle_system, neighbor_system)
end
```
For many users, this means a hard breaking change, as it's not configurable.

I'm not asking to undo this decision, I'm just asking to make this optional to allow users to stay with the old, well-known style.

### Additional contract requirements

SciMLStyle must retain its post-#729 nesting behavior by default and allow users to select the prior YAS-style nesting through the `yas_style_nesting` keyword of `format_text`. When enabled, continuation lines align with the opening construct.
