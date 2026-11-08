Implement gzip compression for HTTP transport
The [spec says](https://github.com/open-telemetry/opamp-spec/blob/main/specification.md#plain-http-transport):

>The Agent MAY compress the request body using gzip method and MUST specify "Content-Encoding: gzip" in that case. Server implementations MUST honour the "Content-Encoding" header and MUST support gzipped or uncompressed request bodies.
>The Server MAY compress the response if the Agent indicated it can accept compressed response via the "Accept-Encoding" header.

### Additional contract requirements

- When an HTTP Agent is started with the `EnableCompression` start setting set to true, each request body it sends must be gzip-compressed and must carry the header `Content-Encoding: gzip`.
- An HTTP Server must accept request bodies that carry `Content-Encoding: gzip` and decompress them before processing the message. It must continue to accept uncompressed request bodies.
- An HTTP Server may send a gzip-compressed response when the request carries `Accept-Encoding: gzip`. A gzip-compressed response must carry `Content-Encoding: gzip`; an uncompressed response is also acceptable.
