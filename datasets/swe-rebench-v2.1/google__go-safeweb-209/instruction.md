Add support to set 2XX statuses that are not 200 and 204
There currently is no way to set any of the 2XX statuses, so Partial Content is not doable.

### Additional contract requirements

The status-setting operation is exposed as the public method `ResponseWriter.SetCode(code StatusCode)`. Calling it before writing a response allows a 2XX status other than 200 or 204, including Partial Content, to be used for that response.
