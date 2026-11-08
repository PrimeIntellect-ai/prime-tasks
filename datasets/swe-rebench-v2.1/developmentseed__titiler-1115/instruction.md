update logging middleware with more request details
We could include more info about the route, path parameters, query parameters, etc like we recently added to the maap-eoapi deployment in https://github.com/MAAP-Project/maap-eoapi/pull/49

https://github.com/developmentseed/titiler/blob/6d1519e9a289a1f1f8e15c04020920f82cf02c60/src/titiler/core/titiler/core/middleware.py#L100-L135

### Additional contract requirements

- The middleware logs through the `titiler.requests` logger at INFO level.
- The log message has the form `Request received: <path> <METHOD>`, where `<path>` is the request path and `<METHOD>` is the HTTP method.
- The logged request record exposes `query_params`, `headers`, `route`, and `path_params` attributes. `query_params` is a mapping of query parameter name to value, `headers` is a mapping of header name to value, `route` is the resolved route template, and `path_params` is a mapping of path parameter name to value.
- Exceptions raised by the wrapped application are re-raised.


- When the request includes the `accept-encoding` header, the logged `headers` mapping must expose its value under the lowercase key `accept-encoding`.
