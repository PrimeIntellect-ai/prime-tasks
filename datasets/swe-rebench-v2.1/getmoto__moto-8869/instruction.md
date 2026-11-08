PutObject If-Match PreconditionFailed not functional
Hello 👋
Just noticed that I'm not getting an exception when attempting to put some s3 behavior under test.

Previously, I think PutObject only support `If-None-Match` conditional header to prevent overwrites, but I noticed they added [`If-Match` support](https://docs.aws.amazon.com/AmazonS3/latest/API/API_HeadObject.html#API_HeadObject_RequestBody) which functions similarly to GetObject/HeadObject (raising if etag doesn't match header).

I'm able to workaround for now by adding a HeadObject call before my put, but not ideal to add calls and change code to support behavior.

Problem and recreation steps:
```python
import boto3
import moto
import pytest
from botocore.exceptions import ClientError

def test_put_if_match():
    """fails"""
    with pytest.raises(ClientError) as exc:
        with moto.mock_aws():
            s3 = boto3.client("s3", region_name="us-east-1")
            s3.create_bucket(Bucket="test_bucket")
            s3.put_object(Bucket="test_bucket", Key="test_key", Body=b"test")
            s3.put_object(Bucket="test_bucket", Key="test_key", Body=b"test2", IfMatch="test")
    err = exc.value.response["Error"]
    assert err["Code"] == "PreconditionFailed"

def test_wo_moto():
    """passes with real bucket/client"""
    with pytest.raises(ClientError) as exc:
        s3 = boto3.client("s3", region_name="us-east-1")
        s3.create_bucket(Bucket="my-redacted-bucket")
        s3.put_object(Bucket="my-redacted-bucket", Key="test_key", Body=b"test")
        s3.put_object(Bucket="my-redacted-bucket", Key="test_key", Body=b"test2", IfMatch="test")
    err = exc.value.response["Error"]
    assert err["Code"] == "PreconditionFailed"
```
