feat: verify the range of the namespace IDs of left and right nodes in the Hasher
# Problem
The [ `Hasher`](https://github.com/celestiaorg/nmt/blob/b04eea51d193f2fa33af6c017979a1516b6865ef/hasher.go#L155) implementation does not verify the range of namespace IDs in the left and right nodes with respect to each other, which is crucial for proper ordering of leaves based on their namespace IDs and for detecting invalidly constructed trees and proofs.

Quoting from Lazy Ledger paper:
> An adversarial consensus node may attempt to produce a block that contains a Merkle tree with children that are not ordered correctly. To prevent this, we can set a condition in nsHash such that there is no valid hash when leftMaxNs ≥ rightMinNs, and thus there would be no valid Merkle root for incorrectly ordered children

The issue was identified as part of https://github.com/celestiaorg/celestia-app/issues/1296
# Acceptance Criteria
- [ ] To modify the [`Hasher`](https://github.com/celestiaorg/nmt/blob/b04eea51d193f2fa33af6c017979a1516b6865ef/hasher.go#L155) implementation by incorporating this additional namespace ID range check for the supplied children nodes. Possibly, the `Hasher` can return an error for invalid inputs. Subsequent refactor needs to take place to properly consume this change.

### Additional contract requirements

The namespace ID range check is performed by `HashNode` on the supplied child
nodes:

- `HashNode` rejects children that are out of order: when the maximum namespace
  ID of the left child is strictly greater than the minimum namespace ID of the
  right child (`leftMaxNs > rightMinNs`), `HashNode` panics.
- `leftMaxNs == rightMinNs` is a valid ordering and must not be rejected. A
  namespace may span across multiple subtrees, so the same namespace ID can be
  the maximum of the left child and the minimum of the right child. This
  intentionally differs from the quoted paper condition, which treats
  `leftMaxNs == rightMinNs` as invalid.
- The invalid-input behaviour is a panic; `HashNode` keeps its existing
  signature and does not return an error.
