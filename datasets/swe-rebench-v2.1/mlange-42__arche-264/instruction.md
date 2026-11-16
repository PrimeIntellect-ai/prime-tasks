Batch-modification of Entities
Modification of entities (add/remove components) could be passible in batches, using a filter.

Advantages:

* Modify many entities without the need to do it outside of a query
* Potential speedup as with entity creation

### Additional contract requirements

`World.Batch()` exposes filtered component modification. `Batch.Add(filter, callback, comps...)` adds the specified components to entities matching the filter, and `Batch.Remove(filter, callback, comps...)` removes the specified components from matching entities. The callback may be nil.
