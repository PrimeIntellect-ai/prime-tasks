blob/s3blob: s3ForcePathStyle stopped working in v0.39.0
### Describe the bug

This was flagged by [goreleaser's tests][build] when dependabot opened the pr updating from v0.38 to v0.39.

[build]: https://github.com/goreleaser/goreleaser/pull/5080

I'm not sure if this is expected and just not documented, or if it is in fact a bug.

### To Reproduce

open a bucket (can be a local minio for example) using `s3ForcePathStyle`.

## Expected behavior

To work.

### Version

v0.39.0

### Additional context

Error:

```
open bucket s3://basic?endpoint=http%3A%2F%2Flocalhost%3A32812&region=us-east&s3ForcePathStyle=true: unknown query parameter "s3ForcePathStyle"
```

Also, forcing `awssdk=v1` makes it work again.

### Additional contract requirements

For S3 bucket URLs, `s3ForcePathStyle=true` is accepted as a legacy spelling for enabling path-style addressing. An S3 request opened with this parameter addresses an object by including the bucket name in the request path (for example, `/mybucket/object`) rather than prepending the bucket name to the request hostname.
