Deprecated Tunnels REST API version is used
## Current behavior

The tool uses v1.1 tunnels REST API endpoint /available_tunnels to get all the tunnels for the user and their org.
The endpoint is a part of API version that Sauce Labs is planning to deprecate in the future.

## Desired behavior

Should use v1 tunnels REST API endpoint /tunnels?all=true&full=true to get all the tunnels for the user and their org.
The endpoint is a part of the supported API version.

### Additional contract requirements

- The tunnels listing is exposed through the existing `listTunnels` API method (and the `listTunnels` CLI command). It targets the v1 `/tunnels` endpoint and accepts the `all` and `full` query parameters, so that a request to `/tunnels?all=true&full=true` can be made.
