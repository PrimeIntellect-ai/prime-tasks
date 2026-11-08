Default to more precise segregation of resumed sessions
It is currently possible to construct two `ClientConfig`s that share a resumption store; this in itself is desirable (eg, see #2260 and openssl-compat). However, those `ClientConfig`s may diverge in ways that make sharing their resumed sessions incorrect. Such as:

1. variance of server certificate validation (in a minor sense, such as different root certs, or a major sense, like whether certificate validation happens at all).
2. variance of client authentication identities,

Getting into that situation doesn't happen by magic, and an application would need to write code to arrange it, but I think it would be surprising.

The best behaviour would be to have resumption keyed on a wider set of data  than just the server name (AFAICT this would mean multiple breaking API changes, because the verifier traits have no equality relation).

An alternative and partial measure would be to reverify the server's certificate on resumption -- this would cost significant performance and only address (1) but not (2). Allowing that separately might be a good idea for other reasons, as we don't really have any reason to assume the output of cert validation is stable over a session.

### Additional contract requirements

- The client connection exposes `handshake_kind(&self) -> Option<HandshakeKind>`. It returns `None` before the handshake completes, `Some(HandshakeKind::Full)` after a full handshake, and `Some(HandshakeKind::Resumed)` after a resumed handshake.
- `ClientConfig` implements `Clone`. A clone shares the same resumption store as the original, so a session stored by one can be resumed by the other.
- When a client declines to resume a session because the configuration is incompatible, it emits a trace-level log message. If the server certificate verifier differs, the message is exactly `resumption not allowed between different ServerCertVerifiers`. If the client authentication certificate resolver differs, the message is exactly `resumption not allowed between different ResolvesClientCert values`.
