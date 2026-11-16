Plug.Test support for repeated request headers
From a [post I wrote on ElixirForum](https://elixirforum.com/t/plug-test-multiple-instances-of-request-headers/49437):

> So, Conn.get_req_header/2 returns [binary()] and I’m trying to figure out how to properly test multiple instances of a header with Plug.Test. Using Conn.Test.put_req_header/3 twice overwrites the header, and doesn’t add the second instance of the header, and it accepts only a single binary() as the value.

I’ve looked at previous issues focussed on adding multiple instances of _response_ headers, but I haven’t seen any issues addressing testing of multiple instances of request headers (where repeated headers are much more common).

Would a PR be entertained to add `Plug.Test.add_req_header/3`? It could be added to `Plug.Conn`, but that seems to be more ripe for a creeping scope request to add `add_resp_header/3`.

`add_req_header/3` is fairly simple. [HIDDEN]

### Additional contract requirements

- Add a public function `Plug.Conn.prepend_req_headers(conn, headers)` in module `Plug.Conn`. It returns an updated `%Plug.Conn{}` whose request headers are the supplied `headers` followed by the connection's existing request headers, so existing headers of the same name are preserved rather than overwritten. `headers` is a list of `{key, value}` pairs of binaries. It raises `Plug.Conn.AlreadySentError` when the connection state is `:sent` or `:chunked`. When the application env `:plug, :validate_header_keys_during_test` is `true`, a non-lowercase key raises `Plug.Conn.InvalidHeaderError`; when it is `false`, such a key does not raise.
- Add a public function `Plug.Conn.merge_req_headers(conn, headers)` in module `Plug.Conn`. It returns an updated `%Plug.Conn{}` in which each supplied `{key, value}` pair replaces the existing request header entry for `key`, leaving the total number of request header entries unchanged when an existing key is overwritten. `headers` may be a map `%{key => value}` or any enumerable of `{key, value}` pairs of binaries. It raises `Plug.Conn.AlreadySentError` when the connection state is `:sent` or `:chunked`. When the application env `:plug, :validate_header_keys_during_test` is `true`, a non-lowercase key raises `Plug.Conn.InvalidHeaderError`.
