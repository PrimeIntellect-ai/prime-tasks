enhancement: add support for `s3.put_object` `IfNoneMatch` option
S3 recently added support for conditional writes: https://aws.amazon.com/about-aws/whats-new/2024/08/amazon-s3-conditional-writes/

https://docs.aws.amazon.com/AmazonS3/latest/API/API_PutObject.html#API_PutObject_RequestParameters

Would be cool to be able to test this using moto!

The issue can be tested with the following snippet
```
import boto3
from moto import mock_aws

with mock_aws():
    s3 = boto3.client("s3", region_name="us-east-1")
    s3.create_bucket(Bucket="test_bucket")

    first = s3.put_object(
        Key="test_object",
        Body="test",
        Bucket="test_bucket",
        IfNoneMatch="*",
    )

    second = s3.put_object(
        Key="test_object",
        Body="another_test",
        Bucket="test_bucket",
        IfNoneMatch="*",
    )

assert second['ResponseMetadata']['HTTPStatusCode'] == 412
```

You can see for yourself that this fails (as in the write to S3 succeeded) using `mock_aws()` while it behaves correctly if I use a real S3 client on a real bucket.
