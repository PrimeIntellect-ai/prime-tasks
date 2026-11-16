ably-go doesn't retry requests to fallback hosts on a timeout
https://sdk.ably.com/builds/ably/specification/main/features/#RSC15l specifies the the conditions of when an Ably SDK should retry a request to a fallback endpoint.

Specifically https://sdk.ably.com/builds/ably/specification/main/features/#RSC15l2 is not implemented.  A request that times out continues to try at the primary endpoint e.g.

`[ERROR] RestClient: failed sending a request Post \"https://rest.ably.io:443/keys/<Ably_key_name>/requestToken\": context deadline exceeded"}`

### Additional contract requirements

- When a request times out and fallback attempts are made, the returned error string must contain `context deadline exceeded (Client.Timeout exceeded while awaiting headers)`.
- For a timeout retry using the default fallback hosts, make six total requests: first to `rest.ably.io`, then to five distinct default fallback hosts.
