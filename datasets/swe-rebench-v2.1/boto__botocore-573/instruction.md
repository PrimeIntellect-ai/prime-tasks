Unable to pass version to s3:CopyObject
I'm trying to copy a specific version of an object from one s3 bucket to another by adding ?versionId=someversion to the CopySource parameter of s3.copy_object. It looks like the code assumes that the value should be urlencoded, so it mangles the value.

```
        args = {
            'CopySource': '/{}/{}?versionId={}'.format(source_bucket, source_key, version),
            'Bucket': dest_bucket,
            'Key': dest_key,
        }
        session.create_client('s3').copy_object(**args)
```

```
DEBUG:botocore.endpoint:Making request for <botocore.model.OperationModel object at 0x108220a50> (verify_ssl=True) with params: {'query_string': {}, 'headers': {u'x-amz-copy-source': '/source_bucket/source_key%3FversionId%3DabCdeCghIjkLmnOp'}, 'url_path': u'/dest_bucket/dest_key', 'body': '', 'method': u'PUT'}
...
botocore.exceptions.ClientError: An error occurred (NoSuchKey) when calling the CopyObject operation: The specified key does not exist.
```

Is there another way to do this?
