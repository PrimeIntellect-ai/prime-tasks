Strip base64 padding in protocol.URLEncodedBase64
### Description

(version: github.com/go-webauthn/webauthn v0.5.0)

It seems the type `protocol.URLEncodedBase64` is, correctly, decoding base64 without padding. ([ref](https://w3c.github.io/webauthn/#base64url-encoding)) however, a frontend tool I'm using to implement webauthn seems to be adding padding to the `publicKey.response.userHandle`.

Now I can strip this out myself, but would it be incorrect for this library to conveniently strip padding automatically given that it's not meant to be there anyway?

### Use Case

_No response_

### Documentation

_No response_
