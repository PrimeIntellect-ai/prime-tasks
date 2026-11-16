X-Forwarded-Proto Multiple Values
I have been investigating an issue with AWS Application Load Balancers forwarding traffic to a JupyterHub instance (that uses Tornado) - and it appears that the AWS ALB can forward traffic with the following header:

`X-Forwarded-Proto: https,https`

However, Tornado only appears to be able to support a singular value:

https://github.com/tornadoweb/tornado/blob/d4094a0c2a7cddc654381c162ee7786d4bf8453b/tornado/httpserver.py#L286

It seems a similar issue affected ASP.NET at one point:

https://github.com/aspnet/BasicMiddleware/issues/18

Although Mozilla document it as only having a single value:

https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Forwarded-Proto

### Additional contract requirements

- When a request carries an `X-Forwarded-Proto` header whose value is a comma-separated list such as `https,https`, the server must treat the request as HTTPS: the handler's `request.protocol` is `https`.
- Header values that are not `http` or `https` must keep the existing behaviour (the protocol stays `http`).
