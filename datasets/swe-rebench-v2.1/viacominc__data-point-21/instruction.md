attach entityId to error
to help with debugging attach entityId to the error object

Line where to add code

https://github.com/ViacomInc/data-point/blob/master/lib/entity-types/resolve-entity/resolve-entity.js[HIDDEN]

### Additional contract requirements

- When entity resolution fails, the rejected error object must have an `entityId` property whose value is the ID of the entity being resolved.
