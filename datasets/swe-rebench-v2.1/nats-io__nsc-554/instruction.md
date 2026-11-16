Role names should be validated
I was looking up what, if any constraints there are with role (operator, account, or user) names and so I tried this.

```
❯ nsc add account foo/bar
[ OK ] generated and stored account key "ACCPV5QZDNXZK3SJSN5RSHO3TVLKPH5GBIXRMAZZU4FJOCYAWDQ3XV3G"
[ OK ] added account "foo/bar"
Error: "foo/bar" not in accounts for operator "stage" in `/Users/ruthb/.nsc/nats`
```

### Additional contract requirements

- When adding an operator, account, or user with a name containing `/`, return an error containing the exact substring `name cannot contain '/' or '\\'`.
