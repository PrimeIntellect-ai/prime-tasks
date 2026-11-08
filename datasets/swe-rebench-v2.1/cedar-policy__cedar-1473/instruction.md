Allow identical duplicates when adding to `Entities`
### Category

User level API features/changes

### Describe the feature you'd like to request

Currently when adding entities to an `Entities` instance an error is returned if any of the added entities have the same `EntityUID` that is already present in the `Entities`. This is good to ensure that there are no accidental errors that would be missed by silently ignoring duplicates. However, there are times when both the principal and the resource may share some parent entities, in which case it may be difficult to know if there are going to be any duplicate entries. To prevent the duplicates from causing errors the list of entities to be added would have to be pre-filtered by the user to contain no duplicates, which means extra work in checking for duplicates and extra work in building a filtered list of entities before addition.

It would be good if there would be a way to add entities to an `Entities` instance which would allow duplicates, but only if the added entity is exactly the same as the entity already present. This may be made the default mode of adding entities, or it may be a separate API. By doing this internally inside the library, any performance penalty of extra duplicate checking and filtering is eliminated, and only the penalty of comparing entities for equivalence remains – a check which is a beneficial sanity check with relatively low cost.

### Describe alternatives you've considered

Alternative for the user is to not keep any `Entities` instances alive except momentarily. Any precomputed entity lists for principal and resource may be kept in data structures that are not handled by this library, deduplicated in those data structures and then simply converted to `Entities` just before the authorization check.

### Additional context

_No response_

### Is this something that you'd be interested in working on?

- [X] 👋 I may be able to implement this feature request
- [ ] ⚠️ This feature might incur a breaking change

### Additional contract requirements

The public `cedar_policy::Entities` API must accept structurally equal duplicates:

- `Entities::from_json_value(json, schema)` returns `Ok` when the input contains two or more structurally equal entities with the same `EntityUID`; the resulting collection contains a single copy of that entity.
- `Entities::from_entities(entities, schema)` returns `Ok` when the input contains two or more structurally equal entities with the same `EntityUID`; the resulting collection contains a single copy of that entity.
- `Entities::add_entities(self, entities, schema)` returns `Ok` when an entity in `entities` is structurally equal to an entity already present in `self`, or to another entity in `entities`; the resulting collection contains a single copy of that entity.

Two entities are "structurally equal" when they have the same `EntityUID`, the same attributes, and the same ancestors (parents).

When two entities with the same `EntityUID` are not structurally equal, `Entities::from_json_value`, `Entities::from_entities`, and `Entities::add_entities` return `Err(EntitiesError::Duplicate)`.

The `Display` representation of `EntitiesError::Duplicate` is ``duplicate entity entry `<euid>```, for example ``duplicate entity entry `User::"alice"```.
