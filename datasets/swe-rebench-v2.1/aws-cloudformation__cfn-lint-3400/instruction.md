CDK generated cfn template resulting in Cfn-lint errors thrown
### CloudFormation Lint Version

cfn-lint 1.3.4

### What operating system are you using?

Mac, linux (Rocky)

### Describe the bug

A latest version of cfn-lint is throwing errors on cdk defined policy (works fine on version 0.87.4)
we define a load balancer and log bucket and connect the two with
`loadBalancer.logAccessLogs(accessLogBucket);`

When cfn-lint is ran on the output template from cdk synth
the AWS::S3::BucketPolicy which we don’t define throws:
```

E3002 '*' was expected
cdk.out/XXStack.template.json:115:8

E3512 {'AWS': {'Fn::Join': ['', ['arn:', {'Ref': 'AWS::Partition'}, ':iam::XXXX:root']]}} is not valid under any of the given schemas
cdk.out/XXStack.template.json:115:8
```

note replace naming and iam roles with XXs

### Expected behavior

Cfn lint should hopefully not flag error from cdk generated stacks.

### Reproduction template

```
"XXAccessLogsBucketPolicyXXXXX": {
   "Type": "AWS::S3::BucketPolicy",
   "Properties": {
    "Bucket": {
     "Ref": "XXXAccessLogsBucketXXXXXX"
    },
    "PolicyDocument": {
     "Statement": [
      {
       "Action": "s3:PutObject",
       "Effect": "Allow",
       "Principal": {
        "AWS": {
         "Fn::Join": [
          "",
          [
           "arn:",
           {
            "Ref": "AWS::Partition"
           },
           ":iam::XXXXXX:root"
          ]
         ]
        }
       },
```
