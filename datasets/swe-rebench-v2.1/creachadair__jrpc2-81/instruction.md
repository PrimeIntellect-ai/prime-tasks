jhttp: Requests with invalid ID structure are incorrectly flagged as notifications
The bridge parses requests with jrpc2.ParseRequests. This correctly detects invalid request ID structure (e.g., `{"bogus":true}`), but this error is not correctly propagated. In particular, ParseRequests does not check for validation errors, and the ID field is `nil` when the structure was invalid.

This causes the bridge to treat the invalid request as a notification, as if its ID were not set at all. It is forwarded to the server, but the server does not see the problem since the ID on that request is not set.

Either a request needs to surface validation errors, or the bridge needs to use a smarter parsing structure.
