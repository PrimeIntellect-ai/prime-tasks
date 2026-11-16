Add template nonce injection
The CSP and XSRF plugins currently put tokens in the request context.

* There needs to be a part of the plugins that can, later on, provide that nonce for a template to render.
* This should ideally work easily with different template implementations
* This will likely happen in the Commit phase of both plugins

### Additional contract requirements

- `safehttp.TemplateResponse` bundles a safe HTML template (`Template *Template`), its data (`Data *interface{}`) and an optional map of function names to functions (`FuncMap map[string]interface{}`).
- `safehttp.DefaultDispatcher.ExecuteTemplate(rw http.ResponseWriter, resp TemplateResponse) error` executes the response's template with its data, writing the output to `rw`. When the response's `FuncMap` is non-empty, its entries are applied to the template before execution, overriding any existing mapping with the same name. It returns an error if the template is not a safe HTML template or if execution or writing fails.
- `csp.Interceptor.Commit(w *safehttp.ResponseWriter, r *safehttp.IncomingRequest, resp safehttp.Response, cfg interface{}) safehttp.Result` makes the request's CSP nonce available to the response template under the name `CSPNonce`, as a function returning the nonce string. A response that is not a template response is left unchanged. If the nonce cannot be retrieved, a 500 Internal Server Error is written.
- `xsrf.Interceptor.Commit(w *safehttp.ResponseWriter, r *safehttp.IncomingRequest, resp safehttp.Response, cfg interface{}) safehttp.Result` makes the request's XSRF token available to the response template under the name `XSRFToken`, as a function returning the token string. A response that is not a template response is left unchanged. If the token cannot be retrieved, a 500 Internal Server Error is written.
