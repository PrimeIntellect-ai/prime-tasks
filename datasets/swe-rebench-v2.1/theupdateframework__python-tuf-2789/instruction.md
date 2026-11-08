urllib3: Handle proxy environment variables
This is filed in anticipation of #2762 getting merged.

urllib3 made a conscious decision to not handle proxy variables -- this is understandable for them but I don't think we can just hand wave the issue away: loads of users are behind dumb corporate proxies and their only way to get software working is proxy variables.

We can implement a small component above urllib3 PoolManager/ProxyManager that handles this. I have a prototype already

### Additional contract requirements

- Add a public class `ProxyEnvironment` in module `tuf.ngclient._internal.proxy`.
- The proxy environment variables honoured are `http_proxy`, `https_proxy`,
  `no_proxy` and `all_proxy`. `no_proxy` is a comma-separated list of hosts; a
  request host is not proxied when it equals an entry, is a subdomain of an
  entry, or an entry is `*`. A leading dot in an entry is ignored.
- `ProxyEnvironment.__init__(self, **kw_args)` accepts arbitrary urllib3 keyword
  arguments (for example `headers`) and uses them when creating the pool
  managers, so that the returned managers carry those settings.
- `ProxyEnvironment.get_pool_manager(self, scheme: str | None, host: str | None)`
  returns a `urllib3.PoolManager` when no proxy applies, and a
  `urllib3.ProxyManager` whose `proxy` attribute is the proxy URL when a proxy
  applies. The manager is cached per proxy URL, including the no-proxy case, so
  repeated calls for the same proxy URL return the same manager object.
- `ProxyEnvironment.request(self, method: str, url: str, **request_kw)` parses
  the URL, selects the manager for its scheme and host, forwards the request to
  that manager and returns its response.
