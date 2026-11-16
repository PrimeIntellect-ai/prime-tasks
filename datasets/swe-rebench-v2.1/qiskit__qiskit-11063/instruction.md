using the preset pass managers
### What should we add?

First the pass manager is awesome I have not used it for a while and it is really powerful and improved a lot. I personally don't see why we need to use the transpile function anymore (we should seriously consider depreciating it). This being said the generate_preset_pass_manager passes I think we should make a bit more user friendly.

I would make it so that

```
pm =  generate_preset_pass_manager(basis_gates = ['cz', 'sx', 'rz'],  coupling_map =[[0,1], [1,2]], optimization_level=3)
```
should work and not need me to make an object CouplingMap to pass into the generate_preset_pass_manager function.
