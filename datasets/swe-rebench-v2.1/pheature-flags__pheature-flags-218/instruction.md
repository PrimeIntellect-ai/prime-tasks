[toggle-core] Add id and type to strategy and segment read models
**Epic:** https://github.com/pheature-flags/pheature-flags/issues/1 Toggle Core
**Package:** https://github.com/pheature-flags/toggle-core

**Description:**

Update read model classes to allow reading strategy and segment id and types.

### Additional contract requirements

Strategy read models must let callers retrieve the strategy identifier with `id()` and its type with `type()`. Their serialized array representation must include the same identifier under `id` and the type under `type`.

Segment read models must let callers retrieve the segment identifier with `id()` and its type with `type()`. Their serialized array representation must include the same identifier under `id` and the type under `type`, alongside the segment criteria.
