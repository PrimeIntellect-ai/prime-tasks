Does not set status codes on operation errors
Raised in a [Cloud Spanner issue](https://github.com/googleapis/python-spanner/issues/38), the returned `GoogleAPICallError` has a `code` and `grpc_status_code` of `None`.

The issue seems to be at:
https://github.com/googleapis/python-api-core/blob/master/google/api_core/operation.py#L135

The `GoogleAPICallError` constructor does not set the code from the `errors` argument so the error code contained within it is being lost.
