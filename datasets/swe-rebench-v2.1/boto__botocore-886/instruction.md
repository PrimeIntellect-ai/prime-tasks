fix_s3_hosts always assumes you're using central aws instead of a local S3.
I've noticed when attempting to generate presigned urls that the logic behind fix_s3_hosts and the virtual styling always assumes you're using AWS S3. [fix_s3_host](https://github.com/boto/botocore/blob/6065566237de957507fc63ae4d3a034c87552adf/botocore/utils.py#L649)

However, we have a local s3 api on top of ceph, as such it throws away our local s3 endpoint and substitutes s3.amazonaws.com, although the presigned urls work when you switch out the virtual path for our local s3, it's a pain.

This is because the [HIDDEN] is always set to 's3.amazonaws.com'

[HIDDEN]

### Additional contract requirements

- When a client is created with a custom `endpoint_url`, requests made through that client must be sent to the provided endpoint; the host must not be rewritten to a central AWS S3 host. For example, a request to a client created with `endpoint_url='https://foo.com'` for `Bucket='mybucket'`, `Key='mykey'` must be sent to `https://foo.com/mybucket/mykey`. Presigned URLs generated through a client with a custom endpoint must retain that endpoint as their URL authority.
