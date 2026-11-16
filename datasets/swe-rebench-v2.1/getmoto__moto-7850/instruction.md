S3: get/head with partNumber is returning 200 status code instead of 206
```
s3 = boto3.resource("s3")
s3.create_bucket(Bucket="bucket")
s3.Object("bucket", "some-key").put(Body="foo")

assert s3.meta.client.head_object(Bucket="bucket", Key="some-key", PartNumber=1)["ResponseMetadata"]["HTTPStatusCode"] == 206
```

Since it's effectively a range request, it should return 206, not 200.  Same for `get_object`.

### Additional contract requirements

- `head_object` and `get_object` accept an optional integer `PartNumber` argument.
- Without `PartNumber`, both return HTTP status 200. `get_object` returns the full object body.
- With `PartNumber=1` on a non-multipart object, both return HTTP status 206 and a `content-range` response header formatted as `bytes 0-{size-1}/{size}` (where `size` is the object size in bytes). `get_object` returns the full object body.
- With `PartNumber` greater than 1 on a non-multipart object, both raise a `ClientError` whose error code is `416` and whose message is `Requested Range Not Satisfiable`.
- The S3 service exposes a public exception class `RangeNotSatisfiable` in `moto.s3.exceptions`. It subclasses `S3ClientError`, can be constructed with no arguments, has HTTP status code `416`, and its message is `Requested Range Not Satisfiable`.
