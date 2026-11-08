S3: LocationConstraints should be validated
Two scenario's:

 - (How) Does AWS complain if the region is incorrect in the same partition?
 - (How) does AWS complain if the region is incorrect in a different partition?

```
s3_resource = boto3.resource("s3", region_name="us-east-2")
s3_resource.create_bucket(Bucket="foobar", CreateBucketConfiguration={"LocationConstraint": "eu-central-1"})
```

```
s3_resource = boto3.resource("s3", region_name="us-east-2")
s3_resource.create_bucket(Bucket="foobar", CreateBucketConfiguration={"LocationConstraint": "us-gov-east-2"})
```

### Additional contract requirements

- A `CreateBucket` request sent to a region-specific endpoint whose `LocationConstraint` is a valid region that does not match the endpoint's region must fail with error code `IllegalLocationConstraintException` and message `The {location} location constraint is incompatible for the region specific endpoint this request was sent to.`, where `{location}` is the supplied `LocationConstraint` value.
- A `CreateBucket` request that includes a `LocationConstraint` while targeting the default `us-east-1` endpoint must fail with error code `InvalidLocationConstraint` and message `The specified location-constraint is not valid`.
- Add a public exception class `IncompatibleLocationConstraintException(location: str)` in the module `moto.s3.exceptions`, representing the first case above. Its error code is `IllegalLocationConstraintException` and its message is `The {location} location constraint is incompatible for the region specific endpoint this request was sent to.`
- Add a public exception class `InvalidLocationConstraintException()` in the module `moto.s3.exceptions`, representing the second case above. Its error code is `InvalidLocationConstraint` and its message is `The specified location-constraint is not valid`.
