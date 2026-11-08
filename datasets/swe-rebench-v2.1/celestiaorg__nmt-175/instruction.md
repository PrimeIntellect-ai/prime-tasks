ValidateNode does not check the exact size of the non-leaf nodes
# Problem
In an NMT, non-leaf nodes all have a particular size that is `2*namespace size + hash output size`.
The `ValidateNode` should take into account this size and validate nodes' size accordingly. However, this is not the case in the current implementation.


# Acceptance Criteria
Incorporate the exact size check to the `ValidateNode` method together with proper unit tests.

### Additional contract requirements

- The public method that performs this check is `Hasher.ValidateNodeFormat(node []byte) error` (referred to as `ValidateNode` above).
- A non-leaf node is valid only when its length is exactly `2*namespace size + hash output size`, i.e. `Hasher.Size()`.
- `ValidateNodeFormat` returns `ErrInvalidNodeLen` when the node length differs from that exact size (whether shorter or longer), and returns `nil` when the length matches exactly.
