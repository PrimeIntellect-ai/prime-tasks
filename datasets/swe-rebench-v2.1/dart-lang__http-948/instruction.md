_ClientSocketException should have a better toString
...and possibly be public so that users who are willing to have `dart:io` specific code can handle the exception explicitly.

### Additional contract requirements

- Its `toString()` must have the format `ClientException with ` followed by the socket exception’s string representation, then `, uri=` and the request URI.
