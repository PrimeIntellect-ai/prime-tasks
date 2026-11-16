Allow opting out of decompression
Automatically decompressing the response is really helpful for the majority of use cases. However, there may be some situations where you want to deal with the compressed data, currently there's no way to do this apart from letting Got decompress the data and then manually re-compressing it yourself afterwards. Obviously that's very inefficient.

I don't expect there to be a huge amount of use cases that would benefit from this, however it's a very simple (+2 lines) backwards compatible change so I think it's worth adding.

One use case that would massively benefit from this is implementing a reverse proxy server with Got.

This option would allow you to reverse proxy gzip responses with Got by just passing the stream directly through. Combined with the upcoming cache support (#284), I think a caching reverse proxy would be a very powerful use of Got.

### Additional contract requirements

The request option for controlling automatic decompression is named `decompress`. It defaults to enabled. Set `decompress: false` to receive compressed response data unchanged; this applies to both promise and stream requests. Uncompressed response data remains unchanged when decompression is disabled.
