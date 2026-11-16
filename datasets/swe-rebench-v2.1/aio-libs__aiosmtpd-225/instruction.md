Current AUTH hook implementation cannot support mechanisms with dash "-" in the name
The current implementation simply searches for `auth_*` methods in the handler, chop off the `auth_` part, and present the chopped name as is to the list of supported authentications.

This means that AUTH mechanisms such as "CRAM-MD5" and "DIGEST-MD5" are not representable.

Fixing this is a bit tricky; the simple trick of replacing "_" with "-" will result in SASL mechanisms that _does_ contain underscore in their names (see [SASL mechanisms registry on IANA](https://www.iana.org/assignments/sasl-mechanisms/sasl-mechanisms.xhtml)) to be not representable.

[HIDDEN]

### Additional contract requirements

- For undecorated AUTH hooks, double underscores (`__`) in the hook name represent dashes (`-`) in the advertised mechanism name, while single underscores remain underscores. A mechanism derived this way must also be accepted by AUTH and invoke its corresponding hook.
- An explicit-name AUTH decorator lets a hook declare its mechanism name. The declared name takes precedence over the name derived from the hook, for both advertised mechanisms and AUTH dispatch.
- The explicit-name decorator is available as `aiosmtpd.smtp.auth_mechanism(name)` and decorates an AUTH hook.
