More efficient filtering for simple relation filters
Currently, all archetypes of relation nodes are iterated if the node matches.

For plain `RelationFilter`, this could be improved by [HIDDEN].

### Additional contract requirements

- For a plain `RelationFilter`, querying a matching relation node should not require traversing all of its archetypes just because they belong to other relation targets.
- A query created with a `RelationFilter` returns exactly the entities that match the filter's inner `Filter` and whose relation target equals the filter's `Target`. This holds both when the filter is passed directly to `World.Query` and when it is registered with `World.Cache` and the resulting `CachedFilter` is passed to `World.Query`.
