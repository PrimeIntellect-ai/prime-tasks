[HIDDEN]
Currently [HIDDEN], which doesn't allow to retrieve the file. This should not be the case, it's in the name - 'instant retrieval'.

[https://github.com/getmoto/moto/blob/c194259b6096a865d2c990984740008c26f8b1d9/moto/s3/utils.py#L37](url)

Current error:
`E           botocore.errorfactory.InvalidObjectState: An error occurred (InvalidObjectState) when calling the GetObject operation: The operation is not valid for the object's storage class
`

AWS documentation:
[https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage-class-intro.html](url)

>

S3 Glacier Instant Retrieval (GLACIER_IR) – Use for long-term data that's rarely accessed and requires milliseconds retrieval. Data in this storage class is available for real-time access.

### Additional contract requirements

Objects stored as GLACIER_IR must be readable immediately. A restore request for a GLACIER_IR object must be rejected as invalid object state because this storage class is not an archive class.
