Client: Add ability to override any default value from resty http transport
Such as timeout, max idle connections, max idle connection per host, disable keep alives, read & write buffer size, etc.

### Additional contract requirements

- Add a public struct `TransportSettings` in package `resty` with these fields:
  - `DialerTimeout time.Duration`
  - `DialerKeepAlive time.Duration`
  - `IdleConnTimeout time.Duration`
  - `TLSHandshakeTimeout time.Duration`
  - `ExpectContinueTimeout time.Duration`
  - `ResponseHeaderTimeout time.Duration`
  - `MaxIdleConns int`
  - `MaxIdleConnsPerHost int`
  - `DisableKeepAlives bool`
  - `DisableCompression bool`
  - `MaxResponseHeaderBytes int64`
  - `WriteBufferSize int`
  - `ReadBufferSize int`
- Add a public function `NewWithTransportSettings(transportSettings *TransportSettings) *Client` in package `resty` that creates a client whose HTTP transport is built from the supplied settings. A nil argument uses Resty's built-in defaults.
- Add a public function `NewWithDialerAndTransportSettings(dialer *net.Dialer, transportSettings *TransportSettings) *Client` in package `resty` that creates a client using the supplied dialer together with the supplied transport settings. A nil dialer or nil settings argument uses Resty's built-in defaults.
- Each `TransportSettings` field configures its corresponding dialer or HTTP transport behavior. For non-nil settings, use each field's supplied value, including zero values; only a nil settings pointer selects Resty's built-in defaults. `DisableKeepAlives` and `DisableCompression` mirror the `net/http.Transport` fields of the same name.
