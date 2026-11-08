HTTP2ChannelHandler.[HIDDEN]
HTTP2ChannelHandler has a [flag](https://github.com/apple/swift-nio-http2/blob/cee48fd87d0ae541cefeee4880d2e419631e9368/Sources/NIOHTTP2/HTTP2ChannelHandler.swift#L64) indicating whether we wrote a frame. We check this before issuing a flush to avoid unnecessary flushes. However, [HIDDEN] after issuing a flush [here](https://github.com/apple/swift-nio-http2/blob/master/Sources/NIOHTTP2/HTTP2ChannelHandler.swift[HIDDEN]). As a result we may emit flushes unnecessarily.

### Additional contract requirements

- A `channelReadComplete` event must not emit a flush when no HTTP/2 frames have been written since the preceding flush. When frames have been written, they must be flushed; a later `channelReadComplete` event with no intervening frame writes must not emit another flush.
