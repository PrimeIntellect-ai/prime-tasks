Support HEAD requests
`HEAD` requests are not supported yet, so we should implement a handler.
Possibly similar or derived from `SimpleGetOperationHandler`.

### Additional contract requirements

- A `HEAD` request for an existing resource must be answered with status 200.
- The response to a `HEAD` request must not include a message body.
- The handler for HEAD requests is named `HeadOperationHandler` and is exported from the package's main index, following the naming of the existing GET, PUT, POST, PATCH and DELETE handlers.
