`from_curl/1` does not return fully formed `Req.Request`
Hey @derekkraan 👋

I ran into a small issue with `CurlReq.from_curl/1`: It does not return a fully formed `Req.Request` and I can't set certain request options on it because they weren't registered.

For example, this shouldn't raise:

```elixir
"some curl command"
|> CurlReq.from_curl()
|> Req.merge(receive_timeout: 15_000)
** (ArgumentError) unknown option :receive_timeout
    (req 0.5.8) lib/req/request.ex:1175: Req.Request.validate_options/2
    (req 0.5.8) lib/req.ex:528: Req.merge/2
    iex:10: (file)
```

It works fine with regular `Req.Request` structs:

```
Req.new()
|> Req.merge(receive_timeout: 15_000)
```

[HIDDEN]

You can verify this by running `req.registered_options` on the `Req.Request` struct returned by `CurlReq.from_curl/1`:

```elixir
iex> req = CurlReq.from_curl("some curl command")
%Req.Request{}
iex> req.registered_options
MapSet.new([:compressed])
```

If you create a request with `Req.new/0`, there are many more options registered:

```elixir
iex> req = Req.new()
%Req.Request{}
iex> req.registered_options
MapSet.new([:http_errors, :redirect_log_level, :follow_redirects, :pool_timeout,
 :redact_auth, :output, :range, :max_redirects, :cache_dir, :aws_sigv4,
 :receive_timeout, :cache, :decode_body, :user_agent, :plug, :path_params_style,
 :retry, :form_multipart, :retry_log_level, :params, :inet6, :unix_socket,
 :pool_max_idle_time, :form, :compressed, :json, :redirect_trusted,
 :decode_json, :auth, :finch_private, :max_retries, :redirect, :path_params,
 :raw, :finch, :compress_body, :checksum, :base_url, :connect_options,
 :finch_request, :retry_delay, :location_trusted])
```

### Additional contract requirements

- A request returned by `from_curl/1` must be a fully formed `Req.Request` that accepts ordinary Req options, including `:receive_timeout`, when passed to `Req.merge/2`.
- For a request returned by `from_curl/1`, the `:redirect` and `:compressed` options must both be `false` by default.
