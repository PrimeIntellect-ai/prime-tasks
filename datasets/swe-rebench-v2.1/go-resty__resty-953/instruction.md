retry not reset multipartFields reader when RetryResetReaders is true
retry not reset multipartFields reader when RetryResetReaders is true

### Additional contract requirements

- When `RetryResetReaders` is true, the readers of multipart fields added with
  `SetMultipartField` must be reset before each retry request is built, so that
  every retry request carries the complete multipart field content.
- If resetting a multipart field reader fails, the retry operation must return a
  non-nil error.


- - If a retry is triggered by an HTTP 500 response and resetting a multipart field reader fails, the operation must return a response with status code 500 as well as a non-nil error.
