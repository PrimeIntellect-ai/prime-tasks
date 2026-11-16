httpMethods is a snapshot from Node 18.12.0 meaning methods from newer versions are unsupported
Why this has been done rather than using `http.METHODS`?

### Additional contract requirements

- The supported HTTP methods must include `QUERY`, and pretty-print output must list `QUERY`.
