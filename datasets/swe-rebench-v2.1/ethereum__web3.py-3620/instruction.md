Some Websocket endpoints don't handle binary communication
### What happened?

During debugging of issues of websocket connections between Ankr (which works) and NodeReal (which doesn't) with the [Subscriptions Example](https://web3py.readthedocs.io/en/latest/subscriptions.html#an-example), I noticed in the debug logs that payloads were sent in binary, vs a `websocket` (library)-based script I built whose payloads I could see in plaintext.

Long story short, it appears not all Websocket servers can handle both.

For web3py's part, `WebSocketProvider.socket_send()` requires request data to be in bytes, which according to the [`websockets` docs](https://websockets.readthedocs.io/en/stable/reference/sync/client.html#websockets.sync.client.ClientConnection.send) is then sent as a binary frame. [HIDDEN]

### Full error output

```shell
web3.manager.RequestManager DEBUG    Sending request to open socket connection: [NodeReal],
    method: eth_subscribe,
    params: ('logs', {'topics': ['0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ea']})
[...]

web3.providers.WebSocketProvider DEBUG    Caching request info:
    request_id=0,
    cache_key=cfcd208495d565ef66e7dff9f98764da,
    request_info={'method': 'eth_subscribe', 'params': ('logs', {'topics': ['0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ea']}), 'response_formatters': (<function apply_formatter_if at 0x1021ea7a0>, <cyfunction identity at 0x10206b6b0>, <cyfunction identity at 0x10206b6b0>), 'subscription_id': None, 'middleware_response_processors': []}

web3.manager.RequestManager DEBUG    Getting response for request from open socket connection:
    request: {'id': 0, 'jsonrpc': '2.0', 'method': 'eth_subscribe', 'params': ('logs', {'topics': ['0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ea']})}

[...]
Timed out waiting for response with request id `0` after 30.0 second(s). This may be due to the provider not returning a response with the same id that was sent in the request or an exception raised during the request was caught and allowed to continue.
```

### Fill this section in if you know how this could or should be fixed

While I intend to relay this to NodeReal for potential infrastructure-based solutions, it may be prudent to allow users to force `WebSocketClient` to use text frames, as we have little control over which platforms support binary communication.

[HIDDEN]

### web3 Version

7.8.0

### Python Version

3.11

### Additional contract requirements

`WebSocketProvider` accepts an opt-in `use_text_frames` option. When enabled, outgoing RPC payloads are sent as text frames without changing their content. When the option is omitted or disabled, outgoing requests continue to use binary frames.
