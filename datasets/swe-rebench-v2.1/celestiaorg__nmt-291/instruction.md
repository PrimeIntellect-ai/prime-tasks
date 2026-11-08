feat: Expose Root Computation from VerifyLeafHashes
### Feature Request: Expose Root Computation from VerifyLeafHashes

**Description:**
Currently, the `VerifyLeafHashes` function in the NMT library performs two operations internally:
1. Computing the root from provided proof and data.
2. Comparing the computed root with an existing root.

To facilitate use cases where root computation alone is required (without immediate comparison), we propose breaking down `VerifyLeafHashes` into two distinct functions. The main goal is to expose the root computation logic separately.

**Proposed Change:**
- Extract root computation into a separate, publicly accessible function, e.g., `ComputeRoot(proof, data)`.
- Update `VerifyLeafHashes` to utilize this new function internally:

```go
func ComputeRoot(proof Proof, data []byte) ([]byte, error) {
    [HIDDEN]
}

func VerifyLeafHashes(proof Proof, data []byte, root []byte) (bool, error) {
    [HIDDEN]
}
```

**Benefits:**
- Allows consumers to recompute roots separately from verification, enabling more flexible use-cases and simplifying proofs.
- Minimal change, reusing approximately 99% of existing code.

**Impact:**
- Non-breaking change, backward-compatible.
- Minor refactor only; no new logic introduced.

Feedback and suggestions are welcome.

### Additional contract requirements

The root computation is exposed through the following public API in package `nmt`:

- Method `Proof.ComputeRootWithBasicValidation(nth *NmtHasher, nID namespace.ID, leafHashes [][]byte, isNamespace bool) ([]byte, error)` computes the Merkle root from the proof and the supplied leaf hashes while performing basic validation. When `isNamespace` is true it additionally validates that the leaf hashes belong to `nID` and that the proof is complete for that namespace. When `isNamespace` is false no namespace consistency check is performed, so a range proof whose leaf hashes span multiple namespaces still yields the correct root.
- Function `ComputeAndValidateLeafHashes(nth *NmtHasher, nid namespace.ID, leaves [][]byte) ([][]byte, error)` validates that every leaf carries the expected namespace prefix and returns the corresponding NMT leaf hashes in the same order as the input.
- Function `ComputePrefixedLeafHashes(nth *NmtHasher, nid namespace.ID, leaves [][]byte) ([][]byte, error)` prepends `nid` to each payload and returns the resulting NMT leaf hashes; for an empty input it returns an empty slice and no error.

Errors returned by these operations contain the following exact substrings:

- `leaf hash does not match the NMT hasher's hash format`
- `failed namespace check`
- `proof range`
- `wrong leafHashes size`
- `invalid leaf data`
- `does not belong to expected namespace`
