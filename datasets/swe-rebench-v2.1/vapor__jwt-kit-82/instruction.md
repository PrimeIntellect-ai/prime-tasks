EdDSA Support
Please consider supporting Ed25519 signature.

### Additional contract requirements

JWTKit must support creating and verifying JWT signatures using the EdDSA algorithm with the Ed25519 curve.

The public API for this is:

- `EdDSAKey.Curve` with an `ed25519` case.
- `EdDSAKey.generate(curve:)` returning a newly generated key pair.
- `EdDSAKey.public(x:curve:)` creating a public-only key from a base64 or base64url encoded public key.
- `EdDSAKey.private(x:d:curve:)` creating a key pair from base64 or base64url encoded public and private key material.
- `JWTSigner.eddsa(_:)` returning a `JWTSigner` that signs and verifies JWTs using EdDSA.

A JWT signed with an EdDSA private key must verify with the matching public key, and the verified payload must equal the original payload. A JWT whose signature does not match the verifying key must be rejected.

JWK (JSON Web Key) values with key type `OKP` and curve `Ed25519` must be usable to verify EdDSA-signed JWTs, including when the key material is supplied in base64 or base64url form.
