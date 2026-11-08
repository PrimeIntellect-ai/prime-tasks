Add support for S3-compatible services
- Backblaze B2
- Minio
- GCS

### Additional contract requirements

- Add a public function `ParseHost(s string) (bucket string, region string, endpoint string, forcePathStyle bool)` in package `github.com/benbjohnson/litestream/s3`.
- The `s3.Replica` type must expose exported fields `Endpoint string` and `ForcePathStyle bool`.
- Add a public function `NewReplicaFromConfig(c *ReplicaConfig, db *litestream.DB) (litestream.Replica, error)` in package `github.com/benbjohnson/litestream/cmd/litestream`.
- `ReplicaConfig` must expose the fields `Path` and `URL`.
- For a generic S3 host such as `test.litestream.io`, `ParseHost` returns the whole host as the bucket, an empty region, an empty endpoint, and `forcePathStyle=false`.
- For a Backblaze B2 host such as `test-123.s3.us-west-000.backblazeb2.com`, `ParseHost` returns bucket `test-123`, region `us-west-000`, endpoint `https://s3.us-west-000.backblazeb2.com`, and `forcePathStyle=true`.
- `NewReplicaFromConfig` must accept a nil `db` argument.
- For `test.localhost:9000`, `ParseHost` returns bucket `test`, region `us-east-1`, endpoint `http://localhost:9000`, and `forcePathStyle=true`; for `test.localhost`, it returns bucket `test`, region `us-east-1`, endpoint `http://localhost`, and `forcePathStyle=true`.
- For `litestream.io.storage.googleapis.com`, `ParseHost` returns bucket `litestream.io`, region `us-east-1`, endpoint `https://storage.googleapis.com`, and `forcePathStyle=true`.

- When configuring an S3-compatible replica, the configured endpoint and path-style setting are used for S3 service requests.
