JWTKit 5.0.0-RC.1 support for Curve25519 types
JWTKit's RC uses its own types to represent common cryptographic types, and then convert into Swift-Crypto types. It would be much more practical, especially when used with other libraries, to use the swift-crypto types themselves. This way we can plug in the private keys we already have, without going through a base64 conversion step and back.

### Additional contract requirements

An existing Swift-Crypto `Curve25519.Signing.PrivateKey` must be usable for EdDSA JWT signing by wrapping it directly in `EdDSA.PrivateKey(backing:)`, without converting its key bytes to and from Base64. An existing Swift-Crypto `Curve25519.Signing.PublicKey` must likewise be usable for verifying EdDSA JWTs by wrapping it directly in `EdDSA.PublicKey(backing:)`, without that Base64 round trip.
