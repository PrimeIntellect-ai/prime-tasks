Allow keep alive connection through the proxy
Once ago there was a merged pr - https://github.com/aio-libs/aiohttp/pull/3070 that disabled keep-alive connections through the proxy. There was a suggestion to make this functionality switchable in discussion.

Keep-alive with the proxy sometimes is need. E.g. to establish ntlm authorization the client must send 2 requests in one connection (a handshake). Current aiohttp logic restricts it, closing the connection on the first request.

I suggest to allow keep-alive connection when client explicitly sets keep-alive header.
