buildRangeProof can panic upon invalid input range
# Problem
The [buildRangeProof](https://github.com/celestiaorg/nmt/blob/master/nmt.go#L244) can panic if the `start` and `end` arguments are invalid.

# Acceptance Criteria
[HIDDEN]

### Additional contract requirements

- Treat `start` as inclusive and `end` as exclusive. Return `ErrInvalidRange` without panicking when `start` is negative, `start` is greater than or equal to `end`, or `end` exceeds the tree’s leaf count.
