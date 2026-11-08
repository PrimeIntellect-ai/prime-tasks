BaseRequest.url passes the host and port to `URL.build` when the port is included in the host header (non-default port)
request.host can be `127.0.0.1:8123`

https://github.com/aio-libs/aiohttp/blob/0b8be7f6c8db0d59afe02109df9be874d0d637e6/aiohttp/web_request.py#L447

yarl 1.13.0+ caught this because host is not validated via https://github.com/aio-libs/yarl/pull/954
