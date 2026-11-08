Provide better error messages when invalid values are passed
It appears I can't use a `Bucket` where an `IBucket` is expected. Example:
Edit: Whoops: looks like I just forgot to include Ref:. We should improve the error messaging to make this more clear.

```
{
  "$schema": "../cdk.schema.json",
  "Resources": {
    "MyBucket": {
      "Type": "aws-cdk-lib.aws_s3.Bucket"
    },
    "MyDist": {
      "Type": "aws-cdk-lib.aws_cloudfront.Distribution",
      "Properties": {
        "defaultBehavior": {
          "origin": {
            "aws-cdk-lib.aws_cloudfront_origins.S3Origin": {
              "bucket": "MyBucket"
            }
          }
        }
      }
    }
  }
}
```

throws the error:

```
Error: Cannot parse class type aws-cdk-lib.aws_s3.IBucket with value MyBucket
```

### Additional contract requirements

- When this input produces an error for `bucket`, the error message must include `Expected static method, got: "bucket"`.
- For the shown input with `bucket` as the property name, and for an `S3Origin` whose entire value is the string `MyBucket`, synthesis must reject with a `TypeError`.
- When an `S3Origin` value is the string `MyBucket`, the error message must include `Expected aws-cdk-lib.aws_s3.IBucket, got: "MyBucket`.
