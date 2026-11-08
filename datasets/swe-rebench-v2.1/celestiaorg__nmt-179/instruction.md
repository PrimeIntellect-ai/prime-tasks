VerifyLeafHashes can panic in the completeness check if proof.nodes are not namespaced
# Problem
Link to the completeness check: https://github.com/celestiaorg/nmt/blob/master/proof.go#L199
The proof.nodes length are not checked before extracting their namespace IDs. This may cause panic.

# Acceptance Criteria
[HIDDEN]

### Additional contract requirements

- Verifying a proof must never panic because a proof node is malformed. If any proof node does not conform to the namespaced node format of the hasher, the verification of `VerifyLeafHashes` must return `false` (with completeness checking enabled), including when the completeness check would otherwise read namespace IDs from that node.
