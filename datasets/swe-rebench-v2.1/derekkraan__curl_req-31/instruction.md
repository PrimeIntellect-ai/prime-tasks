Support insecure connection / `-k` Flag
We would need to pass down options to `finch`/`mint` to skip SSL verification.

This could be set in req like

```elixir
Req.get!(url, connect_options: [transport_opts: [verify: :verify_none]])
```

For more information see: https://hexdocs.pm/req/0.5.8/Req.Steps.html#run_finch/1


> ` -k, --insecure      Allow insecure server connections when using SSL`

### Additional contract requirements

- `CurlReq.to_curl/2` emits the short `-k` flag when the request's `connect_options` set `transport_opts: [verify: :verify_none]`. For a GET request to `http://example.com` the output is exactly `curl -k -X GET http://example.com`; with proxy `http://my.proxy.com:2233` the output is exactly `curl -k -x "http://my.proxy.com:2233" -X GET http://example.com`.
- `CurlReq.from_curl/1` (and the `~CURL` sigil) recognizes the `-k` and `--insecure` flags and returns a `%Req.Request{}` whose `registered_options` include `:connect_options` and whose `options[:connect_options]` include `transport_opts: [verify: :verify_none]`.
- For `curl -k --proxy my.proxy.com:2233 http://example.com`, `options[:connect_options]` is exactly `[proxy: {:http, "my.proxy.com", 2233, []}, transport_opts: [verify: :verify_none]]`.
