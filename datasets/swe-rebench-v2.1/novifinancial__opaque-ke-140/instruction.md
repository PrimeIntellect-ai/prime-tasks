Generics for public objects should all rely on Ciphersuite
RegistrationRequest, RegistrationResponse, RegistrationUpload currently have type parameters that are not CipherSuite, and they should be fixed to be CipherSuite for consistency.

### Additional contract requirements

`RegistrationRequest`, `RegistrationResponse`, and `RegistrationUpload` each take a single type parameter that implements `CipherSuite` (for example, `RegistrationRequest<CS: CipherSuite>`).

Each of these three types exposes a public `deserialize(input: &[u8]) -> Result<Self, ProtocolError>` method and implements `TryFrom<&[u8]>` with `Error = ProtocolError`, so that `RegistrationRequest::<CS>::try_from(bytes)`, `RegistrationResponse::<CS>::try_from(bytes)`, and `RegistrationUpload::<CS>::try_from(bytes)` are available.
