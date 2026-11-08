Wrong target reported when using AutoDependencyTracking and HTTP_PROXY environment variable
On our environment we're using request library together with HTTP_PROXY setting. All dependency requests that go through proxy have target of 443 (this are https requests).

As I've debugged through the code, it looks like [HttpDependencyParser.getDependencyTelemetry](https://github.com/microsoft/ApplicationInsights-node.js/blob/6a772adb58dcd1a1e5577dfb071efa7414326db2/AutoCollection/HttpDependencyParser.ts#L49) gets the url without protocol in such case. For example `host.example.com:443`. With such value, the parser treats host.example.com as protocol name, and 443 as host name. This gives useless results as `target` value and also - if we have multiple hosts - all of them are aggregated into one 443 value.

I'd like to have real host value in the target field, the same as it is in case, when no HTTP_PROXY is used.

### Additional contract requirements

- For protocol-less URL strings, dependency telemetry `data` must be `https://a.bing.com:443/search` for `a.bing.com:443/search` and `http://a.bing.com:123/search` for `a.bing.com:123/search`.
- For protocol-less URL strings, dependency telemetry `target` must be `a.bing.com:443` for `a.bing.com:443/search` and `a.bing.com:123` for `a.bing.com:123/search`, and `name` must be `GET /search` when the request method is `GET`.
