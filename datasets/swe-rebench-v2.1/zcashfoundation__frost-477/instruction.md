[NCC-E008263-4VP] Unchecked Accesses to Data Structures
In multiple instances, dictionary are accessed directly, which leads to panics if the key is not present. See report for more details.

Also, in `aggregate()`, we should make sure that the 3 arguments have matching sets of identifiers.

Fix those:

- It's probably better to avoid indexing directly altogether and use `.get()` instead, handling the error. Try enabling the [`indexing_slicing` lint ](https://rust-lang.github.io/rust-clippy/master/index.html#/indexing_slicing) (possibly with an exception in test code)
- Add a validation in `aggregate()` to make sue the identifier sets are consistent (`signing_package.signing_commitments` and `signature_shares` should have equal keys, and they should be a subset of `pubkeys.signer_pubkeys`)
