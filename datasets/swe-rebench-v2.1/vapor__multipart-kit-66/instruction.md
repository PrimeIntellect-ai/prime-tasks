Decoding String enum
<!-- 🚀 Thank you for contributing! --->

### Describe the bug

Server show the error on a multipart/form-data request with a String enum  - "Could not convert value at "license" to type License from multipart part. for key license". Earlier versions of multipart-kit work as expected. At least 4.0.0.

```
enum License: String, Codable, CaseIterable {
    case dme1
}
```

### To Reproduce

<!-- Tell us how to reproduce this issue. -->
<!-- Please provide as much detail as possible (the more code snippets, the better)! -->
<!-- If we cannot recreate it, we will not be able to figure out how to fix it. -->

Steps to reproduce the behavior:
1. Send a multipart/form-data request from a client with a String enum.
2. Try decoding the request in a Content conform struct on the server.
3. Server shows the error.

### Expected behavior

Correct decoding String enum.

### Environment

<!-- We must know your exact environment or it is very difficult to help. -->
<!-- Hint: use `vapor --version` in the root directory of your Vapor project. -->

* Vapor Framework version: 4.47.0
* OS version: Ubuntu 20.04, macOS 11.4
* multipart-kit: 4.2.0
