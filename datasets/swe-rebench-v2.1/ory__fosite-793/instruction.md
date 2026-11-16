openid session storage should be deleted when the authcode is exchanged
### Preflight checklist

- [X] I could not find a solution in the existing issues, docs, nor discussions.
- [X] I agree to follow this project's [Code of Conduct](https://github.com/ory/fosite/blob/master/CODE_OF_CONDUCT.md).
- [X] I have read and am following this repository's [Contribution Guidelines](https://github.com/ory/fosite/blob/master/CONTRIBUTING.md).
- [ ] I have joined the [Ory Community Slack](https://slack.ory.sh).
- [ ] I am signed up to the [Ory Security Patch Newsletter](https://ory.us10.list-manage.com/subscribe?u=ffb1a878e4ec6c0ed312a3480&id=f605a41b53).

### Ory Network Project

_No response_

### Describe the bug

I work on a project that use fosite as a golang package and implements the fosite storage interfaces in a custom way. The `DeleteOpenIDConnectSession` interface has never been called and more recently has been marked deprecated. However, this is a problem for the fosite storage interfaces.

The storage interfaces are very nicely designed and gives implementors lots of flexibility in how the underlying storage works. In our project, for several technical reasons (including that we are not using SQL), each storage interface gets stored in the underlying datastore separately, with no connection to each other. Because the openid sessions are never deleted, we have no choice but to allow them to linger for longer than is actually necessary, using up storage in the underlying datastore.

If I understand the code correctly, there is no reason to keep the openid session data after the authcode is successfully exchanged [HIDDEN]

I understand that other implementations of the storage interface might choose to store the openid session data along with the authcode session data (e.g. together in a SQL table), and therefore incur less overhead in the underlying datastore. It's nice that the fosite storage interface gives that flexibility. However, the storage interfaces should not require or assume that style of implementation, and none of the other fosite storage interfaces require it except for the openid interface.

Might you consider accepting a PR which [HIDDEN] Storage interfaces which do not need it could simply implement it as an empty (no-op) function, which they are most likely already doing anyways.

### Reproducing the bug

In the source code, you can see that the `DeleteOpenIDConnectSession` is never called, and is marked deprecated.

### Relevant log output

_No response_

### Relevant configuration

_No response_

### Version

v0.44.0

### On which operating system are you observing this issue?

None

### In which environment are you deploying?

None

### Additional Context

_No response_

### Additional contract requirements

- The stored OpenID Connect session that is deleted is the one associated with the authorization code that was exchanged for tokens.
- If deleting the stored OpenID Connect session fails, the token endpoint response population must fail with a server error (`fosite.ErrServerError`).
- `DeleteOpenIDConnectSession` remains a supported storage operation and is not deprecated.
