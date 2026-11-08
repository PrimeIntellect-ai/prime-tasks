JSON marshal of VerificationResult yields incorrectly-formatted in-toto attestation
**Description**

Due to in-toto moving to protobuf, there is an issue where marshalling `VerificationResult` (with `json.Marshal`) will produce a JSON object with an incorrectly formatted in-toto statement.

Specifically, the `predicateType` field is named `predicate_type`, and other fields are made into snake_case instead of the expected `camelCase` as [required by spec.](https://github.com/in-toto/attestation/blob/main/spec/v1/predicate.md)
