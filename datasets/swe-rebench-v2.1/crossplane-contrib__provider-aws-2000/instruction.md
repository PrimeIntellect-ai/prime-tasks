RDSInstance doesn't set username in `writeConnectionSecretToRef` if you are importing an existing resource

### What happened?
If I import an existing RDSInstance that has been orphaned, the username in the `writeConnectionSecret` is never set because its only ever set in the `create` workflow.


### How can we reproduce it?
Create an RDSInstance using
```
deletionPolicy: Orphan
writeConnectionSecretToRef:
  name: foobar
  namespace: foobar1
forProvider:
...
   masterUsername: foo
   masterPasswordSecretRef:
     key: pass
     name: secret
     namespace: secret
...
connectionDetails:
    - fromConnectionSecretKey: endpoint
    - fromConnectionSecretKey: port
    - fromConnectionSecretKey: username
    - fromConnectionSecretKey: password
```

Delete the Secret/manifests

### What environment did it happen in?
Crossplane version:
V0.46.0
