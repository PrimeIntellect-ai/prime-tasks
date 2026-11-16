ESO keeps pushing the same parameter for every sync when it's type is `SecureString`
**Describe the bug**
When pushing an encrypted parameter (through KMS) to `AWS Parameter Store`, ESO currently creates different versions from the same parameter on each sync interval. This happens because ESO compares a remote encrypted parameter value with a non-encrypted one, resulting in a new push.

**To Reproduce**
Steps to reproduce the behavior:
1. Create a `PushSecret` to push a parameter with `SecureString` parameter type.
3. Watch the new version of the same secret to be created in every ESO iteration

**To Fix**
[HIDDEN]

**Expected behavior**
I expect ESO to update the remote secret only when the secret value is different from the remote one.

**Screenshots**
<img width="1552" alt="bug_evidence" src="https://github.com/user-attachments/assets/6bd17986-09a1-49fd-a936-2b32fcb1f477">

**Additional context**
This bug was introduced after this [PR](https://github.com/external-secrets/external-secrets/pull/3576) added support to push parameters with `SecureString` values.

### Additional contract requirements

- When checking whether an existing remote `SecureString` parameter differs from the source secret, retrieve its value in decrypted form for comparison.
- If a remote `SecureString` parameter's returned value is exactly `sensitive`, return the error `unable to compare 'sensitive' result, ensure to request a decrypted value`.
