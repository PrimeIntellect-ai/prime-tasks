Calls to the Wikibase API should throw an exception if no network is available
There does not seem to be any timeout on HTTP requests issued by WDTK. So, if we attempt to make an HTTP request via WDTK while disconnected from the network, the call will stall indefinitely.
It should rather throw an exception after a user-configurable timeout.

### Additional contract requirements

- `org.wikidata.wdtk.wikibaseapi.ApiConnection` provides a public method `int getConnectTimeout()` that returns the current connect timeout in milliseconds, and a public method `void setConnectTimeout(int timeout)` that sets the maximum time to wait for establishing a connection, in milliseconds.
- `org.wikidata.wdtk.wikibaseapi.ApiConnection` provides a public method `int getReadTimeout()` that returns the current read timeout in milliseconds, and a public method `void setReadTimeout(int timeout)` that sets the maximum time to wait for a server response after a connection is established, in milliseconds.
- A negative value passed to either setter disables that timeout, and a negative value returned by either getter means that no explicit timeout is set. The default value for both timeouts is negative, so no timeout is applied unless a nonnegative value has been configured.
- When a nonnegative connect timeout is configured, it is applied to the `java.net.HttpURLConnection` used for API calls; when a nonnegative read timeout is configured, it is applied to that connection. Negative values are not applied.
