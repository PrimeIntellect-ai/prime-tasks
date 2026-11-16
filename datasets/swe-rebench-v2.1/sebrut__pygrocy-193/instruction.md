Add path in request when creating base url
If grocy in not host at the root of a web server but in an other directory every request failed due to the base_url not complete.
This is done in line https://github.com/SebRut/pygrocy/blob/8787acc6d4f5f16169894810e21ba09b0b4f831d/pygrocy/grocy_api_client.py#L294

In this case the port may be add behind a full path like http://grocy.localdomain/grocy/public/:80/api/stock
Wich can't be available.

### Additional contract requirements

The API client constructor accepts an optional argument named `path` for the installation subdirectory. When supplied, requests must address the API beneath that subdirectory; when omitted, requests must retain the root-hosted URL behavior. The port remains part of the host authority, before any subdirectory and the API path.
