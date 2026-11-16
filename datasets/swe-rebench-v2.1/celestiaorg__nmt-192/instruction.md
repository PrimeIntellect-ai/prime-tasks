overlap between empty proofs and absence proofs
## Problem
 In NMTs, an empty `proof` is defined as a proof that satisfies two conditions: (1) it contains an empty range i.e., `proof.start == proof.end`, and (2) its `nodes` field is empty. [HIDDEN] This can lead to situations where a proof can be treated as both an absence proof and an empty proof, depending on the order of operations (depends on which type is checked first). Specifically, a proof that satisfies conditions (1) and (2) but has a non-empty `leafHash` will pass both [`IsEmptyProof()`](https://github.com/celestiaorg/nmt/blob/34cf84ca83cd7596504a2e809083b82b5775bcfe/proof.go#L110) and [`IsOfAbsence()`](https://github.com/celestiaorg/nmt/blob/34cf84ca83cd7596504a2e809083b82b5775bcfe/proof.go#L68) checks.

The following test demonstrates this inconsistency:
```go
	// create an NMT with 8 sequentially namespaced leaves, numbered from 1 to 8.
	tree := exampleNMT(1, 1, 2, 3, 4, 5, 6, 7, 8)
	root, err := tree.Root()
	assert.NoError(t, err)
	dummyValue := createByteSlice(tree.treeHasher.Size(), 0x01)
	// this proof is neither a well-formed absence proof nor a well-formed empty proof
	proof := Proof{start: 1, end: 1, leafHash: dummyValue, nodes: [][]byte{}}
	assert.True(t, proof.IsOfAbsence())  // this check passes while proof is not a well-formed absence proof, this result is misleading
	assert.True(t, proof.IsEmptyProof()) // this check passes while proof is not a well-formed empty proof, this result is misleading

	// the proof is not a proper empty proof, yet it can be used as a valid empty proof
	isVerified := proof.VerifyNamespace(tree.treeHasher.baseHasher, []byte{10}, [][]byte{}, root)
	assert.True(t, isVerified)
```

### Additional contract requirements

- An empty proof must have an empty range (`start == end`), no proof nodes, and an empty `leafHash`. A proof with a non-empty `leafHash` must not be classified as empty.
- Namespace verification must reject a proof with an empty range, no proof nodes, and a non-empty `leafHash` rather than accepting it as an empty proof.
