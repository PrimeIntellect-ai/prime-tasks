Update the `github.com/spdx/tools-golang`dependency to `v0.5.0`.
### What would you like to be added?

Currently, Ratify uses tools-golang v0.3.0. The most recent release is v0.5.0. This version has support for SPDX 2.3.

The Kubernetes BOM tool now generates SPDX 2.3 documents and it would be useful to be able to support them.

### Anything else you would like to add?

_No response_

### Are you willing to submit PRs to contribute to this feature?

- [X] Yes, I am willing to implement it.

### Additional contract requirements

- The `github.com/spdx/tools-golang` dependency is at version `v0.5.0`.
- `BlobToSPDX(bytes []byte) (*spdx.Document, error)` is a public function in package `plugins/verifier/licensechecker/utils`. It parses SPDX tag-value documents of version 2.3 or earlier into the returned document, where `DocumentName` is available directly on the document. It returns an error when the tag-value input cannot be parsed.
- The SBOM verifier processes valid SPDX 2.3 JSON documents successfully and returns an error for JSON documents that are not valid SPDX.
