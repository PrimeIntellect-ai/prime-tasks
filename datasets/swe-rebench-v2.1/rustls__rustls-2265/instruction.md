Support `certificate_authorities` extension in ClientHello
**Checklist**
* [x] I've searched the issue tracker for similar requests

**Is your feature request related to a problem? Please describe.**
The TLS 1.3 [`certificate_authorities`](https://datatracker.ietf.org/doc/html/rfc8446#section-4.2.4) extension in ClientHello can be used by the client to communicate to the server what CAs it recognizes, helping the server present a certificate acceptable to the client. Currently, this is not supported in `rustls`.

**Describe the solution you'd like**
We can add this extension to the `ClientHello` type (e.g., as the `.certificate_authorites_extension()` method), and add a default function to the `ServerCertVerifier` trait that asks for CA names that the server cert verifier recognizes. With these changes, custom `ServerCertVerifier`s on the client side can communicate their recognized CAs to the server during TLS handshake, and custom cert resolvers on the server side can take this information into account when picking a cert/key.

I've already started prototyping this, and if the maintainers are OK with the proposed solution, I can open a PR for this feature.

### Additional contract requirements

- Add a default method `root_hint_subjects(&self) -> Option<&[DistinguishedName]>` to the
  `ServerCertVerifier` trait (in `rustls::client::danger`). It returns the distinguished names of
  the certificate authorities the verifier trusts, or `None` when no hint is provided; its default
  implementation returns `None`. When it
  returns `Some`, the client includes those names in the TLS 1.3 `certificate_authorities`
  ClientHello extension. The extension is only applicable to TLS 1.3 and is not sent for TLS 1.2.
- Add a method `certificate_authorities(&self) -> Option<&[DistinguishedName]>` to
  `rustls::server::ClientHello`. It returns the distinguished names advertised by the client in the
  `certificate_authorities` extension, or `None` when the client did not send the extension. For
  TLS 1.2 connections it returns `None`.
- `DistinguishedName` is the public type `rustls::DistinguishedName`.
