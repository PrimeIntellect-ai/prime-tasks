Resuming a resumable upload from GCS C++ client does not work: fake-gcs-server rejects “Content-Range: bytes */*”
When resuming a resumable upload using `gcs::RestoreResumableUploadSession()`, the C++ client sends `Content-Range: bytes */*`:
https://github.com/googleapis/google-cloud-cpp/blob/1178ef9bbb0257e940dc2d9af475802d8bb37038/google/cloud/storage/internal/rest_client.cc#L699

fake-gcs-server rejects this: https://github.com/fsouza/fake-gcs-server/blob/e2d2de125a3c14829c3f063681f37aa7e8095444/fakestorage/upload.go#L594

AFAIK this syntax is valid.

### Additional contract requirements

- The server must accept a resumable-upload request that carries `Content-Range: bytes */*` (the syntax sent by the C++ SDK when restoring a resumable upload session) rather than rejecting it. Acceptance means the response is not a client error (4xx); the exact success status is not fixed, so either a completed upload (e.g. `200 OK`) or a resumable-upload status response (e.g. `308 Resume Incomplete`) is acceptable.
