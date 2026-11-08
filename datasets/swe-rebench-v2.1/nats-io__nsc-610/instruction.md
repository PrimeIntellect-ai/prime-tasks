Wrong output in `nsc reissue operator`
### What version were you using?

nsc version 2.8.0
nats-server version 2.9.22


### What environment was the server running in?

Linux VM, arm64, docker images:

- nats:2.9.22-scratch
- natsio/nats-box:0.13.9

### Is this defect reproducible?

1. Run `nsc reissue operator --convert-to-signing-key`

### Given the capability you are leveraging, describe your expectation?

The output should show the old key being turned into a signing key
```
[ OK ] operator "O" successfully changed identity to: {new_key}
[ OK ] old operator key "{old_key}" turned into signing key
```

### Given the expectation, what is the defect you are observing?

The output shows the new key as the old operator key:
```
$ nsc reissue operator --convert-to-signing-key
[ OK ] operator "O" successfully changed identity to: OBUGUUS5PYPNSNXCZ6TYAHYYKW5L2CH3XXTZW5IJPVCCR4CORRONC7JH
[ OK ] old operator key "OBUGUUS5PYPNSNXCZ6TYAHYYKW5L2CH3XXTZW5IJPVCCR4CORRONC7JH" turned into signing key
all jobs succeeded
```
