SASL EXTERNAL incorrectly requires a password to be set
### Description

SASL EXTERNAL doesn't work correctly unless e.g. `auth_password` is set.

Big capability refactor (#2341, specifically 0401ae9f9e6745ee7b899f8620fcea0d0a61c056) likely caused this, but I didn't go back and test an older revision. Just building on @half-duplex's sleuthing from a session working on #2362 earlier tonight.

### Reproduction steps

1. Provide a `client_cert_file` path (`.pem` file), `auth_method = sasl` and `auth_target = EXTERNAL` in Sopel's config file.
  a. I registered the certificate fingerprint with a NickServ account for completeness, but this shouldn't be required to repro.
2. Start Sopel and wait for it to connect.
3. Sopel will quit with an error:

```
[2023-11-12 01:11:12,806] sopel.bot            INFO     - Client capability negotiation list: away-notify, chghost, invite-notify, multi-prefix, sasl, userhost-in-names
[2023-11-12 01:11:12,839] sopel.coretasks      ERROR    - Configuration error on ACK capability "sasl": ConfigurationError: SASL authentication required but no password available; please check your configuration file.
[2023-11-12 01:11:12,871] sopel.irc            ERROR    - ERROR received from server: Closing Link: your.host.name ()
```

### Expected behavior

Successful SASL EXTERNAL authentication:

```
[2023-11-12 01:11:42,497] sopel.irc            INFO     - Connected, initiating setup sequence
[2023-11-12 01:11:43,763] sopel.bot            INFO     - Client capability negotiation list: away-notify, chghost, invite-notify, multi-prefix, sasl, userhost-in-names
[2023-11-12 01:11:43,920] sopel.coretasks      INFO     - Successful SASL Auth.
[2023-11-12 01:11:43,920] sopel.bot            INFO     - End of client capability negotiation requests.
[2023-11-12 01:11:44,001] sopel.coretasks      INFO     - Enabled client capabilities: chghost, multi-prefix, userhost-in-names, away-notify, sasl
```

### Relevant logs

_No response_

### Notes

@half-duplex added a very simple patch for this already in #2362 (see below). I'm just opening this issue so we don't forget about this bug, regardless of whether SCRAM-SHA-256 support makes it into 8.0.0 or not.

```patch
diff --git a/sopel/coretasks.py b/sopel/coretasks.py
index 22f7fe1f..97c44849 100644
--- a/sopel/coretasks.py
+++ b/sopel/coretasks.py
[HIDDEN]
+    [HIDDEN]
         raise config.ConfigurationError(
             'SASL authentication required but no password available; '
             'please check your configuration file.',
```

### Sopel version

51300a1ab854d6ec82d90df1bc876188c03335ff

### Installation method

`pip install`

### Python version

_No response_

### Operating system

_No response_

### IRCd

_No response_

### Relevant plugins

_No response_

### Additional contract requirements

- With SASL `auth_target = EXTERNAL`, the absence of a password must not block SASL negotiation. Sopel must proceed with EXTERNAL authentication and resume capability negotiation after successful authentication.
