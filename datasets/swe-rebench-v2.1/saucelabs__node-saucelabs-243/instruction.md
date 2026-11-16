remove us-east-1 datacenter
## Expected Behavior

All datacenter and their APIs exist. Currently, running `sl --headless` doesn't not work

## Actual Behavior

us-east-1 was EOLed some time ago


## Specifications

  - Version:
  - Platform:
  - Subsystem:

### Additional contract requirements

- For region `us-east-4`, `getAPIHost(sauceAPI.servers, sauceAPI.basePath, {region: 'us-east-4'})` must return `https://api.us-east-4.saucelabs.com/rest`, and `getAssetHost({region: 'us-east-4'})` must return `https://assets.us-east-4.saucelabs.com`.
- Requests using the legacy `headless` option must not be routed to the EOLed `us-east-1` datacenter.
