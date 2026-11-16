Archetype graph
Currently, on archetype transition the engine searches for the matching archetype by brute force using the components bitmask.

This could be improved by constructing an archetype graph. Each archetype would hold a list of which archetypes are reached by adding or removing a certain component type.

![grafik](https://user-images.githubusercontent.com/44003176/217200459-dca5790e-0373-446a-9f0a-5253db1e899b.png)

Image source: [ajmmertens.medium.com](https://ajmmertens.medium.com/building-an-ecs-2-archetypes-and-vectorization-fe21690805f9)

### Additional contract requirements

- Add a method `findOrCreateArchetype(start *archetype, add []ID, rem []ID) *archetype` on `World` in package `ecs`. It returns the archetype reached from `start` by removing the component IDs in `rem` and adding the component IDs in `add`, creating that archetype if it does not exist yet.
- The archetype reached from an archetype `a` by adding component `id` is read with `a.GetTransitionAdd(id)`, returning `(*archetype, bool)`. The archetype reached by removing component `id` is read with `a.GetTransitionRemove(id)`, returning `(*archetype, bool)`. The boolean reports whether such a cached transition exists.
