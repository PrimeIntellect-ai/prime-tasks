Add trusted_proxies option
### Search for duplicate feature request

- [X] I already searched, and this feature request or improvement is not a duplicate.

### Feature scope

Configuration (e.g. TOML) or CLI/env option

### Feature request related to a problem

The `log_remote_address` option currently always logs the contents of the `X-Forwarded-For` header. This is problematic when static-web-server is used without a trusted proxy in front, because a client could send this header and "poison" the log. More details can be found [in this MDN document](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Forwarded-For#security_and_privacy_concerns).

### Describe the solution you'd like

I would like a `trusted_proxies` option which would allow specifying from which IP addresses the `X-Forwarded-For` header is allowed to be read. I have actually already implemented this in https://github.com/static-web-server/static-web-server/commit/4cfa56978cda6b3bb3cbf88d8a2b72499db55c0f.

### Describe alternatives you've considered

An alternative would be to have a boolean `trust_x_forwarded`, which toggles the option for all IPs. This is not as fine grained though.

### Build target

All targets

### Additional context

My original Plan was to just submit a draft PR with the changes i made. Before doing that i looked for a Contributing.md file. When opening the PR i was a bit surprised to see the policy that PRs will only be accepted with a related issue, so it would be awesome if a contributing.md file is created :)

### Additional contract requirements

- When X-Forwarded-For logging is enabled and the request's remote address is trusted, the request log entry includes a `real_remote_ip=<ip>` field, where `<ip>` is the client IP taken from the `X-Forwarded-For` header.
- `log_forwarded_for` defaults to `false`; when it is `false` no `real_remote_ip` field is logged.
- `trusted_proxies` defaults to an empty list, which means every remote address is trusted. When the list is non-empty, only remote addresses contained in it are trusted.
- On the command line, `--trusted-proxies` takes a comma-separated list of IP addresses and `--log-forwarded-for` is a boolean flag.
