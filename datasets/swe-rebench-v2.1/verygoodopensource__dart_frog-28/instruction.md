fix: bad state: The 'read' method can only be called once
**Description**

Seeing the following:

```sh
Asynchronous error
Bad state: The 'read' method can only be called once on a shelf.Request/shelf.Response object.

package:shelf/shelf_io.dart 143:11  handleRequest
```

When running the example and visiting `http://localhost:8080` in the browser.
