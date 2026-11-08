Unmarshaling into an interface{} instead of structs
I'm trying to work with Amazon S3 Bucket Policies, which are polymorphic enough that not even the AWS SDK team has attempted to model the rules for them with Go structs. So I'm trying to decode the S3 Bucket Policy JSON into an `interface{}`.

Here's some rough code, extracted from my project.

```go
type S3BucketPolicy interface{}

var bucketPolicy S3BucketPolicy

request := client.GetBucketPolicyRequest(&s3.GetBucketPolicyInput{
    Bucket: &bucketname,
})

// Errors are acceptable
response, _ := request.Send(ctx)

if response != nil && response.Policy != nil && *response.Policy != emptyString {
    if err := json.Unmarshal([]byte(*response.Policy), &bucketPolicy); err != nil {
        exitErrorf(err)
    }
}
```

Using `encoding/json`, this works just fine. However, after dropping-in `github.com/segmentio/encoding/json` as a replacement, I receive the following error:

```
Error: json: cannot unmarshal {"Version":"2012-10-17","Statement":[{"Sid":"AWSCloudTrailWrite","Effect":"Allow","Principal":{"Service":"cloudtrail.amazonaws.com"},"Action":"s3:PutObject","Resource":"arn:aws:s3:::BUCKET/AWSLogs/ACCOUNTID/*","Condition":{"StringEquals":{"s3:x-amz-acl":"bucket-owner-full-control"}}},{"Sid":"AWSLogDeliveryWrite","Effect":"Allow","Principal":{"Service":"delivery.logs.amazonaws.com"},"Action":"s3:PutObject","Resource":"arn:aws:s3:::BUCKET/AWSLogs/ACCOUNTID/*","Condition":{"StringEquals":{"s3:x-amz-acl":"bucket-owner-full-control"}}},{"Sid":"AWSLogDeliveryAclCheck","Effect":"Allow","Principal":{"Service":"delivery.logs.amazonaws.com"},"Action":"s3:GetBucketAcl","Resource":"arn:aws:s3:::BUCKET"},{"Sid":"AWSELBWrite","Effect":"Allow","Principal":{"AWS":"arn:aws:iam::ACCOUNTID:root"},"Action":"s3:PutObject","Resource":"arn:aws:s3:::BUCKET/*"},{"Sid":"AWSAclCheck","Effect":"Allow","Principal":{"Service":"cloudtrail.amazonaws.com","AWS":"arn:aws:iam::ACCOUNTID:user/logs"},"Action":"s3:GetBucketAcl","Resource":"arn:aws:s3:::BUCKET"},{"Sid":"AWSRedshiftWrite","Effect":"Allow","Principal":{"AWS":"arn:aws:iam::ACCOUNTID:user/logs"},"Action":"s3:PutObject","Resource":"arn:aws:s3:::BUCKET/*"}]} into Go value of type main.S3BucketPolicy
```

Here is the JSON (pretty printed), which is valid:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AWSCloudTrailWrite",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com"
      },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::BUCKET/AWSLogs/ACCOUNTID/*",
      "Condition": {
        "StringEquals": {
          "s3:x-amz-acl": "bucket-owner-full-control"
        }
      }
    },
    {
      "Sid": "AWSLogDeliveryWrite",
      "Effect": "Allow",
      "Principal": {
        "Service": "delivery.logs.amazonaws.com"
      },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::BUCKET/AWSLogs/ACCOUNTID/*",
      "Condition": {
        "StringEquals": {
          "s3:x-amz-acl": "bucket-owner-full-control"
        }
      }
    },
    {
      "Sid": "AWSLogDeliveryAclCheck",
      "Effect": "Allow",
      "Principal": {
        "Service": "delivery.logs.amazonaws.com"
      },
      "Action": "s3:GetBucketAcl",
      "Resource": "arn:aws:s3:::BUCKET"
    },
    {
      "Sid": "AWSELBWrite",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNTID:root"
      },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::BUCKET/*"
    },
    {
      "Sid": "AWSAclCheck",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com",
        "AWS": "arn:aws:iam::ACCOUNTID:user/logs"
      },
      "Action": "s3:GetBucketAcl",
      "Resource": "arn:aws:s3:::BUCKET"
    },
    {
      "Sid": "AWSRedshiftWrite",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNTID:user/logs"
      },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::BUCKET/*"
    }
  ]
}
```

Is this use-case supported?
