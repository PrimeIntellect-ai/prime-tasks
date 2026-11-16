Supports "Host" custom header for DataSources
<!-- Please only use this template for submitting enhancement requests -->

**What would you like to be added**:

Implement functionality to ensure the `Host` header in custom requests works as expected.

**Why is this needed**:

In Go's `net/http` package, as detailed at [net/http Request.Header](https://pkg.go.dev/net/http#Request.Header), setting the `Host` header in custom requests doesn't work as users anticipate. The package currently drops the `Host` header, leading to unexpected behavior. We should align the actual behavior with user expectations, improving the custom HTTP request handling in Go.
