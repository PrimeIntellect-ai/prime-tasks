Feature: Automatically pull configuration from nyc.config.js
Currently this can be done with the following in package.json:
```json
{
  "nyc": {
    "extends": "./nyc.config.js"
  }
}
```

It would be nice to make this automatic.  This is useful over `.nycrc` in situations where you need to use logic to determine the correct configuration.  In some cases the config needs to be different based on the version of node.js or platform.  This can be useful to enable `check-coverage` for certain versions of node, for example if a module ponyfills functionality from newer versions of node, test coverage will be low on versions of node where the feature exists natively.
