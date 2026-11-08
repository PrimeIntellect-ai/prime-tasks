[Toggle Model] Create Strategy factory for our existing Toggle strategy types
**Epic:** https://github.com/pheature-flags/pheature-flags/issues/2 Toggle Model
**Package:** https://github.com/pheature-flags/toggle-model

**Description:**

Currently, we only have two types of ToggleStrategy implemented, the EnableByMatchingSegment class and EnableByMatchingIdentityId.

We need to create a factory that implements the ToggleStrategyFactory. This factory should be able to create instances of both Toggle Strategy types.

### Additional contract requirements

- Add a public class `Pheature\Model\Toggle\StrategyFactory` implementing `Pheature\Core\Toggle\Read\ToggleStrategyFactory`.
- `StrategyFactory::create(string $strategyId, string $strategyType, ?Segments $segments = null): ToggleStrategy` returns an `EnableByMatchingSegment` instance when `$strategyType` is `EnableByMatchingSegment::NAME` and an `EnableByMatchingIdentityId` instance when `$strategyType` is `EnableByMatchingIdentityId::NAME`. The created strategy is built from the supplied `Segments` collection; when no collection is supplied, an empty `Segments` collection is used. For any other `$strategyType`, it throws `Pheature\Core\Toggle\Exception\InvalidStrategyTypeGiven`.
- `StrategyFactory::types(): array` returns `[EnableByMatchingSegment::NAME, EnableByMatchingIdentityId::NAME]`.
- `EnableByMatchingSegment::NAME` is the string `enable_by_matching_segment`.
- `EnableByMatchingIdentityId::NAME` is the string `enable_by_matching_identity_id`.
- Add a public class `Pheature\Model\Toggle\IdentitySegment` with constructor `__construct(string $id, array $criteria)`.
- `EnableByMatchingIdentityId::__construct(Segments $segments)` throws `InvalidArgumentException` when the collection contains a segment that is not an `IdentitySegment`.
- `EnableByMatchingIdentityId::jsonSerialize()` and `EnableByMatchingSegment::jsonSerialize()` return an array with a `type` key (the strategy's `NAME`) and a `segments` key holding the array representation of each segment; each segment is represented as an array with `id` and `criteria` keys.
