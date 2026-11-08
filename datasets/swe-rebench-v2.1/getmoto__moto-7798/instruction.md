resourcegroupstaggingapi get_resources doesn't properly filter on s3:bucket
When using the `get_resources` method from the resource groups tagging api with `s3:bucket` as an entry in `ResourceTypesFilters`, no S3 Buckets are being returned. Moto seems to only return S3 buckets when `s3` is provided as a filter rather than the full `s3:bucket`

Here's a snippet that shows the issue:

```python
@mock_aws
class MyTestClass(unittest.TestCase):
    def setUp(self):
        s3 = boto3.resource("s3", region_name="us-east-1")
        s3.create_bucket(Bucket="test-bucket")
        s3.BucketTagging("test-bucket").put(
            Tagging={
                "TagSet": [
                    {"Key": "foo", "Value": "bar"}
                ]
            }
        )

    def test_stuff(self):
        boto3.client("resourcegroupstaggingapi", region_name="us-east-1").get_resources(
                    ResourceTypeFilters=["s3:bucket"]
                )["ResourceTagMappingList"] # Empty list! This should be returning the bucket

        boto3.client("resourcegroupstaggingapi", region_name="us-east-1").get_resources(
                    ResourceTypeFilters=["s3"]
                )["ResourceTagMappingList"] # This does work and returns the bucket properly
```

`s3:buckets` is a valid type filter that works in the real AWS API, and is even called out in the docs as an example https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/resourcegroupstaggingapi/client/get_resources.html. It seems that moto should support this as well.

Relevant Versions:
moto - 5.0.9
boto3 - 1.34.135
Python - 3.11.6
MacOS - 14.5
