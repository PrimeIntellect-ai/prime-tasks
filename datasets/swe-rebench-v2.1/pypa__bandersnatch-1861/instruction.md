Add SOCKS support to proxy configuration parameter
Doing a docs diff we found that the proxy bandersnatch.conf does not work correctly with SOCKS proxies. Let's tweak the code that checks for SOCKS URLs to check the proxy option in the config as well as the environment variables.

### Additional contract requirements

- Add a public function `proxy_address_from_env() -> str | None` in module `bandersnatch.config.proxy`. It detects an HTTP or SOCKS proxy address from the process environment, including OS-specific sources, by reading urllib's `getproxies()`. When proxies for several protocols are present it returns the address for the first protocol in the precedence order `socks5`, `socks4`, `socks`, `https`, `http`, `all`; if none of those is present it returns `None`.
- Add a public function `get_aiohttp_proxy_kwargs(proxy_url: str) -> Mapping[str, Any]` in module `bandersnatch.config.proxy`. For a URL whose scheme is `http` or `https` (case-insensitive) it returns `{"proxy": proxy_url, "trust_env": True}`. For a URL whose scheme is `socks4` or `socks5` (case-insensitive) it returns a mapping containing a `connector` key whose value is an `aiohttp_socks.ProxyConnector`. For any other scheme it returns an empty mapping.
- The `mirror.proxy` configuration option accepts HTTP and SOCKS proxy URLs. When it is set, the configured proxy is used for the mirror's requests; when it is not set, a proxy is taken from the environment. A SOCKS proxy (from either source) is applied to the master's client session as an `aiohttp_socks.ProxyConnector`.
