Consistently remove hop-by-hop headers
Hop-by-hop headers are stripped from buffer mode responses as of #7, but we should ensure they are stripped from forwarded requests and responses in both stream and buffer mode.


https://tools.ietf.org/html/draft-ietf-httpbis-p1-messaging-14#section-7.1.3

### Additional contract requirements

- The hop-by-hop headers are `connection`, `keep-alive`, `proxy-authenticate`, `proxy-authorization`, `te`, `trailer`, `transfer-encoding` and `upgrade`.
- For forwarded requests, preserve the relative order of the headers that remain after hop-by-hop headers are removed.
