Token creation has side effect
With an auth config such as:

```json
{
  "auth": {
    "secret": "...",
    "jwt": {
      "issuer": "...",
      "audience": "...",
      "expiresIn": "7d"
    }
  }
}
```

Calling  only once `app.service('/authentication').create({payload: {userId: _id}, jwt: {expiresIn: '10m'}})` internally will produce a side effect which is that subsequent create call (such as the `app.authenticate()` sent by the feathers-client) will generate tokens with `10m` expiration instead of `7d`.

Modules:
```json
    "feathers": "^2.0.3",
    "feathers-authentication": "pre",
    "feathers-authentication-jwt": "^0.3.1",
    "feathers-configuration": "^0.4.1",
    "feathers-errors": "^2.5.0",
    "feathers-hooks": "^1.7.1",
    "feathers-hooks-common": "^3.0.0-pre.1",
    "feathers-legacy-authentication-hooks": "^1.0.0",
    "feathers-mongoose": "^5.0.3",
    "feathers-rest": "^1.6.0",
```

### Additional contract requirements

When an authentication service create call supplies JWT options, the token returned by that call must honor those options, including a supplied expiration. A per-call expiration override must not change the configured expiration used by later creates that omit an override.
