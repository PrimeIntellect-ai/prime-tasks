Registry server: Allow nil bodies in create resource endpoints
Create resource endpoints currently allow empty string but not nil (e.g. [here](https://github.com/apigee/registry/blob/main/server/registry/actions_apis.go#L37)). The server should be permissive and allow both nil and empty string.
