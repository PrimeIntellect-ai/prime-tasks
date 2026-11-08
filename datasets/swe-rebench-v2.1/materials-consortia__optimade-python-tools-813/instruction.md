ParserError's should not return 500 HTTP status codes
When the Lark parser is unable to parse a filter in an unhandled way, we throw a `ParserError`, which inherits directly from `Exception` and thus the server treats it as a 500 Server Error.

Instead this should raise a 400 Bad Request and return the Lark error message.

This is something that has been biting OPTIMADE implementations that use k8s, as 500 is treated as "down endpoint" status code (cc @shyamd).
