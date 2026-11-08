minio-py fails erroneously with minio.error.InvalidEndpointError: InvalidEndpointError: message: Amazon S3 hostname should be s3.amazonaws.com
I have minio installed to our kubernetes cluster on amazon. The hostname ends in amazonaws.com but is not S3. When I run the minio-py with the correct credentials, the code fails here:

https://github.com/minio/minio-py/blob/master/minio/helpers.py#L276-L279

The check for s3 ignores the fact that I may have an external IP exposed through amazon that is not s3, but rather minio - in this case hosted on our kubernetes cluster.

Do you need a pull request?
