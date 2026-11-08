Client utilizes HTTP response compression by default
 **Is your feature request related to a problem? Please describe.**
Google Maps Services APIs support response compression, taking advantage of this mechanism provides latency and bandwidth improvements, the JavaScript client library currently does not by default .

 **Describe the solution you'd like**
Let's add an Accept-Encoding header for "gzip" to signal to the server that our client can handle compressed content.  Axios, the underlying HTTP client used by this library supports gzip compression transparently.

 **Describe alternatives you've considered**
Having usage of gzip compression be opt-in which a user of this library could do currently by using a custom Axios client instead of the default one provided (See: Client.ts).

The opt in approach is not preferred for two reasons:
1. It assumes that users of this client library will discover that the compression mechanism exists on their own which is poorly communicated.
2. It's fair to assume most applications are IO bound and *not* CPU bound and thus the additional CPU overhead of decompressing is worth the outsize benefit or reducing data sent over the wire.

 **Additional context**
The Go and Java libraries already take advantage of response compression and this would make the JS client more consistent with these other language variants.

### Additional contract requirements

- The default client sends an `Accept-Encoding` header with the value `gzip`.
- A client created with a `config` also sends `Accept-Encoding: gzip` by default.
- A caller can override the `Accept-Encoding` header through `config.headers`; setting it to `identity` opts out of compression.


- The outgoing request headers must expose this header under the exact key `Accept-Encoding`.
