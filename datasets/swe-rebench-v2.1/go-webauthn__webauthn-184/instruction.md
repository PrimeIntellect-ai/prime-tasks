[HIDDEN]
### Version

0.9.1

### Description

> Its value’s [name](https://w3c.github.io/webauthn/#dom-publickeycredentialentity-name), [displayName](https://w3c.github.io/webauthn/#dom-publickeycredentialuserentity-displayname) and [id](https://w3c.github.io/webauthn/#dom-publickeycredentialuserentity-id) members are REQUIRED.

but when a user is registering for the first time the RP might not require the user to enter their name and the displayName might be empty, which would then get omitted and cause an error in JavaScript when calling `navigator.credentials.create`.

### Reproduction

1. Create a user with an empty displayName
2. Pass user to `wa.BeginRegistration`.
3. Encode the result as JSON
4. Pass to `navigator.credentials.create`

### Expectations

Expectation is that the resulting JSON would contain `displayName: ''` but instead `displayName` is undefined.

### Documentation

https://w3c.github.io/webauthn/#dom-publickeycredentialcreationoptions-user
