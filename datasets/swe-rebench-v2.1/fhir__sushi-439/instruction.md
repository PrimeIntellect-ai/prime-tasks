Repeated Slices are Allowed
If we have profile A with a slice on component called foo:
```
Profile: A
Parent: Observation
* component contains foo 0..1
```
And then we make a profile B that inherits from A, and we incorrectly slice component again with foo:
```
Profile: B
Parent: A
* component contains foo 1..1
```
We end up with two `Observation.component:foo` elements in the snapshot and differential. This is isn't correct, and we should probably either:
1) Ignore the `contains` and apply the card rules or flag rules to the original foo slice, while warning the user that using `contains` has no effect.
2) Ignore all the rules including card and flag rules, and emit an error indicating that you can't put an existing slice in a contains.

See https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/profiling.20on.20external.20IG.20and.20named.20slices for some more details.
