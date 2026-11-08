Listing users is not implemented in the Auth Emulator
<!-- DO NOT DELETE
validate_template=true
template_path=.github/ISSUE_TEMPLATE/bug_report.md
-->

I just found a feature which isn't implemented and I really need this. I thought I'll submit an issue for this.

**firebase-tools:**
v8.14.1

**Platform:**

MacOS 10.15.7

### [REQUIRED] Test case

```
import * as admin from "firebase-admin"
admin.initializeApp()s
admin.auth().listUsers(10)
```

### [REQUIRED] Steps to reproduce

Try to call `admin.auth().listUsers(10)`

### [REQUIRED] Expected behavior

I'd like to be able to query all users at once (or rather, in batches of 1000) from Firebase Auth.

### [REQUIRED] Actual behavior

It crashes with

```
identitytoolkit.projects.accounts.batchGet is not implemented in the Auth Emulator:
```

```
An internal error has occurred. Raw server response: "{"error":{"code":501,"message":"identitytoolkit.projects.accounts.batchGet is not implemented in the Auth Emulator.","errors":[{"message":"identitytoolkit.projects.accounts.batchGet is not implemented in the Auth Emulator.","reason":"unimplemented"}],"status":"NOT_IMPLEMENTED"}}"
```

### Additional contract requirements

The Auth Emulator's account-listing operation must return project user accounts rather than an unimplemented error. A caller must be able to request a batch of 1000 accounts. If more accounts remain than fit in a batch, the response must provide a continuation token that lets the caller retrieve subsequent batches until the accounts have been listed.
