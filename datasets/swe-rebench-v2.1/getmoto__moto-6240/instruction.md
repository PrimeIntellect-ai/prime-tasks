mock_s3 get_object should not return VersionId when bucket doesn't have versioning
Even though the S3 document says that "Objects that are stored in your bucket before you set the versioning state have a version ID of null." However, when you do [get_object](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/s3/client/get_object.html), if the bucket doesn't have versioning, the response doesn't have the key ``"VersionId"``. However, moto will return ``"VersionId": "null"`` (a string).

I believe you should change this line of code https://github.com/getmoto/moto/blob/master/moto/s3/models.py#L1812
