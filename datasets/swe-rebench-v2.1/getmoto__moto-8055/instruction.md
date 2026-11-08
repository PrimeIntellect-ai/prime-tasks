S3 HeadObject does not support range header
The real S3 API supports the `range` header on a HeadObject request, even though the response body is empty. Some clients, like TransferManager used by tensorflow-io, send HeadObject requests with a range header to determine the content length up front. But when used with moto server they will receive a 416.

##  MRE

Run moto server on port 3000:
```
moto_server -p3000
```

Create bucket, object and head object request:
```python
import boto3
import io

# Create a mock S3 client
s3 = boto3.client('s3',
                  endpoint_url='http://localhost:3000', aws_access_key_id="foo", aws_secret_access_key="bar")

# Create a bucket
bucket_name = 'my-tfrecord-bucket'
s3.create_bucket(Bucket=bucket_name)

## Put object
response = s3.put_object(
    Bucket='my-tfrecord-bucket',
    Key='hello',
    Body='world'
)

## Head object request with range
s3.head_object(
    Bucket='my-tfrecord-bucket',
    Key='hello',
    Range='bytes=0-9'
)
```

Errors with:
```
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "../.venv/lib/python3.11/site-packages/botocore/client.py", line 565, in _api_call
    return self._make_api_call(operation_name, kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "../.venv/lib/python3.11/site-packages/botocore/client.py", line 1017, in _make_api_call
    raise error_class(parsed_response, operation_name)
botocore.exceptions.ClientError: An error occurred (416) when calling the HeadObject operation: Requested Range Not Satisfiable
```

moto 5.0.13

### Additional contract requirements

A `HeadObject` request that includes a satisfiable `Range` header must succeed and return the standard HTTP range response headers, while the response body remains empty:

- `Content-Range` is formatted as `bytes {begin}-{end}/{total_size}`, where `{begin}` and `{end}` are the resolved, inclusive byte offsets clamped to the object size and `{total_size}` is the full object size.
- `Content-Length` equals the number of bytes in the resolved range.
- For a 2-byte object, `Range: bytes=0-9` and `Range: bytes=0-` both yield `Content-Range: bytes 0-1/2` and `Content-Length: 2`; `Range: bytes=-1` and `Range: bytes=1-1` both yield `Content-Range: bytes 1-1/2` and `Content-Length: 1`.
- A `Range` header whose start offset is greater than its end offset (for example `bytes=1-0`) is treated as a non-range request: the full `Content-Length` is returned and no `Content-Range` header is set.
- A `Range` header that is not satisfiable (for example `bytes=5-9` or `bytes=100-` on a 2-byte object) must fail with error code `416` and a message containing `Range Not Satisfiable`.
