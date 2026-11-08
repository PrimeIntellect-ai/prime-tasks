Make protocol error wrap error that caused it.
### Description

I'm trying to authenticate a user using discoverable login.

If credentials are not found in the database I want to tell the user to remove credentials which they just tried to use.
For that I return my sentinel `ErrCredentialsNotFound` from `DiscoverableUserHandler` so I can extract it down the line and tell the user it doesn't exist. However my sentinel error doesn't get wrapped inside `FinishDiscoverableLogin` but being turned into a string in `ValidatePasskeyLogin` in [login.go](https://github.com/go-webauthn/webauthn/blob/b9a233f627c94835e5ad3d2bc4a63dd55140580b/webauthn/login.go#L253)

But even if it was wrapped with for example `fmt.Errorf` it wouldn't help because `protocol.Error`'s field `Details` [is a string](https://github.com/go-webauthn/webauthn/blob/b9a233f627c94835e5ad3d2bc4a63dd55140580b/protocol/errors.go#L77)

```go
var webAuthnUserId uint64
creds, err := a.webAuthn.FinishDiscoverableLogin(func(rawID, userHandle []byte) (user webauthn.User, err error) {
    credsId := strconv.FormatUint(idBytesToUint64(rawID), 10)
    rawUser, err := a.GetWebAuthnUserByWebauthnID(ctx, idBytesToUint64(userHandle))
    webAuthnUserId = idBytesToUint64(userHandle)
    if err != nil {
        return nil, fmt.Errorf("failed to fetch user: %w", err)
    }

    creds, err := a.GetUserWebAuthnCredentialsById(ctx, idBytesToUint64(userHandle), credsId)
    if errors.Is(err, sql.ErrNoRows) {
        return nil, ErrCredentialsNotFound
    }

    if err != nil {
        return nil, fmt.Errorf("failed to fetch user credentials: %w", err)
    }
    rawUser.credentials = []webauthn.Credential{creds}

    return rawUser, nil
}, session, r)

if errors.Is(err, ErrCredentialsNotFound) {
    return "", time.Time{}, errors.Join(ErrInvalidCredentials, err)
}
```
What I want is to have an ability to unwrap `protocol.Error` to get errors that caused it.
[HIDDEN] And according to your readme you are at version 0 and breaking changes should be expected.

As per my case I can work around it by declaring a flag outside my handler function and setting it inside when I encounter a sentinel error just like I'm setting `webAuthnUserId`. But it would be better if it was inside of the error returned from `FinishDiscoverableLogin`.

### Use Case

_No response_

### Documentation

_No response_

### Additional contract requirements

- When a protocol error has an underlying cause, callers must be able to inspect that cause through Go's standard error-unwrapping behavior. In particular, an error returned by `DiscoverableUserHandler` must remain identifiable with `errors.Is` when it is returned through `FinishDiscoverableLogin`.
