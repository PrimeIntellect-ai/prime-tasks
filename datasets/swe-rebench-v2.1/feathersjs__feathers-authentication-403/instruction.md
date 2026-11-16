remove method failed with JsonWebTokenError: invalid token
### Steps to reproduce

Call `DELETE /authentication` with a valid JWT in the header results in an error.

[HIDDEN]

```javascript
  remove (id, params) {
    const defaults = this.app.get('auth');
    [HIDDEN]
    // TODO (EK): return error if token is missing?
    return this.passport
      .verifyJWT(accessToken, merge(defaults, params))
      .then(payload => {
        return { accessToken };
      });
  }
```

### Expected behavior
No error

### Actual behavior
Error is thrown. `JsonWebTokenError: invalid token`

### System configuration

**Module versions** (especially the part that's not working):
```
+-- feathers@2.0.3
+-- feathers-authentication@1.0.2
+-- feathers-authentication-jwt@0.3.1
```
**NodeJS version**: 6.9.1

**Operating System**: Windows 10

**Browser Version**: Chrome 55.0.2883.87 m

**Module Loader**: Node.js

### Additional contract requirements

- `remove` must accept a valid JWT supplied in the Authorization header, either directly or with the `Bearer` scheme, without an error.
