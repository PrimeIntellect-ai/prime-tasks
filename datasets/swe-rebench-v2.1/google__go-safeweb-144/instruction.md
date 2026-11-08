Get rid of Interceptor keys in ServeMux, since they aren't needed.
Currently `Interceptors` are installed and stored using unique keys in the `ServeMux`. We have decided these keys aren't needed and should be removed. If interaction is needed between a `Handler` and an `Interceptor` then the interceptors needs to implement package level functions that take `ResponseWriter`s and `IncomingRequest`s and modify the context when state needs to be passed.

### Additional contract requirements

- `(*safehttp.ServeMux).Install` takes a single `safehttp.Interceptor` argument and returns nothing.
- `safehttp.NewResponseWriter` takes a `safehttp.Dispatcher` and an `http.ResponseWriter` and returns a `*safehttp.ResponseWriter`.
