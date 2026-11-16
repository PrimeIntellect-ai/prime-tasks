Bug: Proofs of Absence can be Forged
# Bug: Proofs of Absence can be Forged

## Problem
The namespaced merkle tree exposes a `VerifyNamespace` method whose documentation states that it "verifies that the namespace is complete and no leaf of that namespace was left out in the proof."

This API allow consumers to write code like the following:

```
proof, namespaceData := getUntrustedProofFor(namespaceId)
// check that the namespaceData was all returned
if proof.VerifyNamespace(sha256.New(), namespaceId, namespaceData, n.Root()) {
    process(namespaceData)
} else {
    return errors.New("prover lied about namespace data")
}
```
Unfortunately, this code is vulnerable. A malicious prover can falsely claim that the namespace is empty, and, as long as he also provides an empty proof, the claim will be accepted.


## Test Case

A simple test case which reproduces the issue is as follows:
```
func TestNMT_forgeNamespaceEmptinessProof(t *testing.T) {
	data := [][]byte{
		append(namespace.ID{0}, []byte("leaf_0")...),
		append(namespace.ID{0}, []byte("leaf_1")...),
		append(namespace.ID{1}, []byte("leaf_2")...),
		append(namespace.ID{1}, []byte("leaf_3")...)}
	// Init a tree with the namespace size as well as
	// the underlying hash function:
	tree := New(sha256.New(), NamespaceIDSize(1))
	for _, d := range data {
		if err := tree.Push(d); err != nil {
			panic(fmt.Sprintf("unexpected error: %v", err))
		}
	}

	root := tree.Root()
	actualLeaves := tree.Get(namespace.ID{0})
	if len(actualLeaves) == 0 {
		t.Fatalf("Get(namespace.ID{0}) should have returned two leaves but returned none.")
	}

	forgedProof := Proof{
		start:                   0,
		end:                     0,
		nodes:                   [][]byte{},
		leafHash:                []byte{},
		isMaxNamespaceIDIgnored: true,
	}

	forged_proof_succes := forgedProof.VerifyNamespace(sha256.New(), namespace.ID{0}, [][]byte{}, root)
	if forged_proof_succes {
		t.Fatalf("Successfully verified proof that non-empty namespace was empty")
	}
}
```

## Root Cause

This behavior is introduced by the following condition [here](https://github.com/celestiaorg/nmt/blob/95e8313eb788b46b30f3f85b20fd9a40bf68d432/proof.go#L107):
```
[HIDDEN]
```

## Suggested Solution

Currently, the handling of empty range proofs is not well defined. [HIDDEN] (Without this special case, it's impossible to check range proofs against the empty tree). This will change the semantics of the NMT, causing some existing test cases to fail.

### Additional contract requirements

- A proof claiming that a namespace has no leaves must not verify when that namespace has leaves in the tree, even when the supplied data and proof are empty.
- An absence proof for an empty tree must remain verifiable.
