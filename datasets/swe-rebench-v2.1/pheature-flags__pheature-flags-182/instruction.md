[Toggle Model] Create a Segment type that finds a match in a collection of values
**Epic:** https://github.com/pheature-flags/pheature-flags/issues/2 Toggle Model
**Package:** https://github.com/pheature-flags/toggle-model

**Description:**

Create a new segment type implementing the Segment interface. It should match when the given value is present in a segment's collection of values.

### Additional contract requirements

- Add a public class `InCollectionMatchingSegment` in namespace `Pheature\Model\Toggle` implementing the `Segment` interface, with a public method `match(array $payload): bool`. It returns `true` only when every criterion defined in the segment matches the corresponding payload value: a scalar criterion matches by strict equality, and a criterion that is a collection matches when the payload value is present in that collection. It returns `false` when there are no criteria, when a criterion's field is missing from the payload, or when any criterion does not match.
- The `SegmentFactory` in namespace `Pheature\Model\Toggle` creates an `InCollectionMatchingSegment` when given the segment type `in_collection_matching_segment`, and lists `in_collection_matching_segment` among its supported types.
