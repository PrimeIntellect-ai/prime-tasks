XSRF Token Generation
In its current format, the XSRF plugin only supports verification of the XSRF token in  the `safehttp.IncomingRequest` body. We also need to generate tokens and add them to a `safehttp.IncomingRequest` context. These will then be injected  by the `htmlinject` plugin as hidden inputs to forms.

### Additional contract requirements

Expose `xsrf.Token(*safehttp.IncomingRequest) (string, error)` so downstream processing can retrieve the token attached to a request's context.

Continue validating XSRF tokens submitted in URL-encoded and multipart request bodies; adding token generation must not replace this verification.
