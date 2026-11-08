AWS LC fails against golang TLS server while ring works fine
**Checklist**
* [x] I've searched the issue tracker for similar bugs.

**Describe the bug**
I've stumbled over a very specific set-up where when using the AWS LC provider, a connection cannot be established while the ring implementation works fine. I'm not 100% sure this is an issue with this crate, but wan't able to trace it down any further.

The set-up: using a server written in golang enforcing TLS 1.2 (I couldn't reproduce the error with a server written in rust with rustls).

**To Reproduce**
The setup is quite large, even though I tried to reduce it as much as I could.

https://github.com/robsdedude/rusttls-ring-vs-aws-issue/tree/4f42dcf51beadce18dc2c44df610a5184bafa0f9

There's plenty more description about the output setup and the observations in the README of the linked repo.

The bottom line is that when using AWS LC, the client fails with
```
Custom { kind: InvalidData, error: InvalidCertificate(BadSignature) }
```
and the server complains
```
remote error: tls: error decrypting message
```

Whereas with `ring` everything works fine. Going through the trace logs, the only difference I could find is that LC offers `ECDSA_NISTP521_SHA512` as `SignatureAlgorithm` while ring doesn't. So I cannot rule out that go's TLS implementation might be at fault here. Sadly I don't know enough TLS details to debug this any further.

### Additional contract requirements

- With AWS-LC, retain `ECDSA_NISTP521_SHA512` in the default signature-scheme list, after `ECDSA_NISTP256_SHA256` and before `ED25519`. For server signature-scheme selection with `TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256`, use the order `ECDSA_NISTP384_SHA384`, `ECDSA_NISTP256_SHA256`, `ECDSA_NISTP521_SHA512`, `ED25519`.
