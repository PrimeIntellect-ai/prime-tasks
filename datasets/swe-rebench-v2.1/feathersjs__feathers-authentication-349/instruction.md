[1.0] Only the first failure is returned on auth failure when chaining multiple strategies
### Steps to reproduce

Register mulitple strategies like so and send a bad username and password.

```js
app.service('authentication').hooks({
  before: {
    create: [
      auth.hooks.authenticate(['jwt', 'local'])
    ]
  }
});
```

### Expected behavior
It should return all failures or return the one for the strategy you were attempting to authenticate with.

### Actual behavior
If you have registered multiple strategies to be checked against, it only returns the first one that fails . This is very misleading as to what the actual error is that caused auth failure.

In the above example it if you provided a bad username and password auth would fail but it would return the failure from the `jwt` strategy, which would be that the token is missing or something.

### System configuration

Tell us about the applicable parts of your setup.

**Module versions**: feathers-authentication@1.0.0-beta

**NodeJS version**: all

**Operating System**: all

**Browser Version**: all

**React Native Version**: all

**Module Loader**: all
