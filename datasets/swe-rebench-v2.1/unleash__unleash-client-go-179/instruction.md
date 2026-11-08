Add app & environment variant override support
### Describe the feature request

At the moment, the SDK doesn't support setting a variant override for `appName` / `environment` despite this being supported by Unleash. Only `userId`, `sessionId`, and `remoteAddress` are supported.

https://github.com/Unleash/unleash-client-go/blob/10a33385c5b131f72c4a179c6efadfeb55e13089/api/variant.go#L55

<img width="920" alt="Screenshot 2024-08-27 at 14 35 12" src="https://github.com/user-attachments/assets/c628dac9-b844-436c-9be5-6815a84a8789">

This is a trivial feature to support, I could open a PR but wasn't sure what the contribution guidelines are on this project.

### Background

_No response_

### Solution suggestions

[HIDDEN]

### Additional contract requirements

- Variant overrides must be able to match the evaluation context's `appName` and `environment` values.
