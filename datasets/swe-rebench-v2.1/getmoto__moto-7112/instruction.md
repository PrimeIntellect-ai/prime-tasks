moto does not enforce S3 object's tag limit
When calling https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/s3/client/put_object_tagging.html with tag set containing more than 10 elements moto does not respect AWS limits https://docs.aws.amazon.com/AmazonS3/latest/userguide/tagging-managing.html and allows to associate more than 10 tags with an object.

Versions:
moto==4.2.11
boto3==1.26.90
s3transfer==0.6.2

### Additional contract requirements

- Setting the tags of an S3 object with `put_object_tagging` accepts a tag set of up to 10 tags, including exactly 10 tags.
- A tag set with more than 10 tags is rejected with an error, so an object never ends up with more than 10 tags.
