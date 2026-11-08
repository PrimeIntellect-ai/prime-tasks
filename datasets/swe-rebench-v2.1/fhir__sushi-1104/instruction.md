Consider populating title/description/name(?) in instances when possible
Authors have to use instances for any conformance resources other than SD, CS, and VS.  These conformance resources often have a `title` and `description`.  We should consider auto-populating these items from keywords (e.g., `Title:`, `Description:`) when the corresponding elements exist in the target instance type.

So far, we've avoided doing so since not all instances have these elements -- and we wanted to be consistent with our behavior across instances.  But in doing so, we're inconsistent w/ our behavior on other conformance types.

We may want to consider making this a configurable option (which means we would need to decide what the default behavior should be).  We also may want to look at the `name` element and see if we should autopopulate that (although the "name" authors give after `Instance:` is already used as the `id`).

See: https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/instance.20title/near/266818927

### Additional contract requirements

For an instance with Definition usage, copy its FSH `Title` and `Description` into the exported resource's corresponding fields when those elements exist on the target resource type. Handle the two fields independently: the presence of one element must not depend on the presence of the other. Do not populate either field when its corresponding element is absent from the target resource type.
