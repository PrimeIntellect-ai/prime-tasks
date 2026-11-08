[TEST] The client adapter does not support streaming responses. Please use :buffer response mode.
I'm receiving the error during tests:
 The client adapter does not support streaming responses. Please use :buffer response mode.

 But I don't understand how to specify that streaming mode is supported.

Config:
`config :reverse_proxy_plug, :http_client, ReverseProxyPlug.HTTPClient.Adapters.HTTPoison`

Elixir version: 1.16.1

### Additional contract requirements

- A globally configured `ReverseProxyPlug.HTTPClient.Adapters.HTTPoison` adapter must be recognized as supporting streaming responses even if its module has not yet been loaded. It must not be rejected solely because of that loading state.
