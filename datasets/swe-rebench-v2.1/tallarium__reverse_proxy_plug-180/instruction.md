Make request header normalization configurable
Hi there!

Request headers are always downcased when sent upstream [here](https://github.com/tallarium/reverse_proxy_plug/blob/master/lib/reverse_proxy_plug.ex#L298).

```elixir
  defp normalize_headers(headers) do
    headers
    |> downcase_headers
    |> remove_hop_by_hop_headers
  end
```

Could the casing be configurable? The upstream we relay requests to through this plug performs case sensitive matching to consume some headers, dropping the ones which have been downcased.

Thanks!

### Additional contract requirements

Callers can configure the casing of request header names forwarded upstream with the `:normalize_headers` option, which accepts a function that receives request headers and returns request headers. The returned header-name casing is retained while forwarding. Without a casing customization, request header names remain lowercased before forwarding. Hop-by-hop request headers are not forwarded, including when request header casing is customized.
