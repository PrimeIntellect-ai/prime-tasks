Cached queries?
Performance of queries could be improved by registering them to the world, and updating their list of archetypes when new archetypes are created.

Currently, queries check archetypes using the filter on every iteration pass. Basically, this check is required only when new archetypes are created.

### Additional contract requirements

Register a filter with `World.Cache().Register(Filter)`. The returned cached filter can be passed to `World.Query` and must yield entities matching that filter, including entities in matching archetypes that existed before registration and archetypes created afterward. Registered queries should avoid rechecking the filter against every archetype on each iteration pass.
