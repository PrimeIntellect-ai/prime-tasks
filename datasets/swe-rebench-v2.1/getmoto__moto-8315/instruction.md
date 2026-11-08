S3 get_object_attributes fails for GLACIER objects
Environment:

Python 3.11
Windows 11 Pro
moto==5.0.20
pytest==8.3.3

My failing test

   ```
 def test_get_glacier_object_attributes(self) -> None:
        s3 = client(
            "s3",
            region_name="eu-west-1"
        )
        s3.create_bucket(
            Bucket="test-bucket",
            CreateBucketConfiguration={"LocationConstraint": "eu-west-1"},
        )

        csv_body = "field_1,field_2\n1,2"

        s3.put_object(
            Body=csv_body.encode("UTF-8"),
            Bucket="test-bucket",
            Key="file.csv",
            StorageClass="GLACIER",
        )

        attributes = s3.get_object_attributes(
            Bucket="test-bucket",
            Key="file.csv",
            ObjectAttributes=["Checksum", "ObjectSize", "StorageClass"],
        )

        assert attributes is not None
```

The error

```
....
if http.status_code >= 300:
            error_info = parsed_response.get("Error", {})
            error_code = error_info.get("QueryErrorCode") or error_info.get(
                "Code"
            )
            error_class = self.exceptions.from_code(error_code)
>           raise error_class(parsed_response, operation_name)
E           botocore.errorfactory.InvalidObjectState: An error occurred (InvalidObjectState) when calling the GetObjectAttributes operation: The operation is not valid for the object's storage class


..\..\.venv\Lib\site-packages\botocore\client.py:1009: InvalidObjectState
```


Expected behaviour is that the call to s3..get_object_attributes(
                    Bucket=bucket,
                    Key=key,
                    ObjectAttributes=["Checksum", "ObjectSize", "StorageClass"],
                )
returns a valid response as it does for non-glacier storage class object
