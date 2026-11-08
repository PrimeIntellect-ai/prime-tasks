[BUG] opensearchapi.Client.Document.Delete bugged error handling (v4)
### What is the bug?
The function `opensearchapi.Client.Document.Delete` has bugged error handling. When it returns an error, for example when attempting to delete a non-existing document, the function rightly returns an error, but this error, instead of being of type `*opensearch.StructError`, is a `*fmt.wrapError` with message `msg`: `"opensearch error response could not be parsed as error: {\"_index\":\"my-index\",\"_id\":\"my-id\",\"version\":4,\"result:\":\"not_found\", <ET CETERA . . . > }"`
The "inner error" at least has the correct "result": "not_found", but this inner error has been wrapped with this parsing error.

### How can one reproduce the bug?
This bug can be reproduced by calling opensearchapi.Client.Document.Delete function on any non-existing document ID.

### What is the expected behavior?
The expectation is to receive an error that can be cast as `*opensearch.StructError` using `errors.As(err, &myStructErr)`, or at the very least, the error should not be wrapped around this parsing error saying the error response could not be parsed as error.

### What is your host/environment?
MacOS Sonoma 14.5
