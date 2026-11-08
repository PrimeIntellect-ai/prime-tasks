Incorrect user-agent
## Bug Description

When debugging #379 it was discovered that the `user-agent` header is reporting `cloudant-node-sdk` instead of `cloudant-couchbackup`.

### 1. Steps to reproduce and the simplest code sample possible to demonstrate the issue

Check the `user-agent` header on any request.

### 2. What you expected to happen

The `user-agent` should report `cloudant-couchbackup` and some version metadata.

### 3. What actually happened

The `user-agent` is `cloudant-node-sdk` + version medata.

Although we set the header here: https://github.com/cloudant/couchbackup/blob/68c802b641673d0a29f560970fb70ce90e18cf56/includes/request.js#L134

[HIDDEN]

## Environment details
- Version(s) that are affected by this issue.
    > 2.7.0
- Node.js version
    > 14.18.1
