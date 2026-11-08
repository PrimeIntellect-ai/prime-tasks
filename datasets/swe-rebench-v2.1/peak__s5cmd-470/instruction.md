NoSuchUpload: The specified upload does not exist
Recently we started to see the error below , couldn't find anything that retries on this case.  It basically fails after getting this error.

`ERROR \"cp data s3://data": MultipartUpload: upload multipart failed upload id: IDXXXXXXXXXX caused by: NoSuchUpload: The specified upload does not exist. The upload ID may be invalid, or the upload may have been aborted or completed. status code: 404, request id: PJXXXXX, host id: HOSTIDXX`

### Additional contract requirements

- The `cp` command accepts an integer flag `--no-such-upload-retry-count` (default `0`).
- When `--no-such-upload-retry-count` is set to a positive value, an upload that fails with a `NoSuchUpload` error is retried up to that many times, and the command succeeds if one of the retries succeeds.
