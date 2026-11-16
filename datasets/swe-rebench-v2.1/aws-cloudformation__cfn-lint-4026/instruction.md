W3037 erroring on wildcard in action
### CloudFormation Lint Version

1.30.0

### What operating system are you using?

Ubuntu 24.04

### Describe the bug

The following policystatements are no longer accepted since version 1.30.0 (W3027 no longer experimental)


We get the following error:

```
W3037 'list*tags' is not one of ['addclientidtoopenidconnectprovider', ...]
```

### Expected behavior

wildcards within actions should be allowed (https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements_action.html)

### Reproduction template

```
{
  "Action": [
    "iam:UpdateAssumeRolePolicy",
    "iam:List*Tags",
    "iam:Tag*",
    "iam:Untag*"
  ],
  "Effect": "Allow",
  "NotResource": {
    "Fn::Sub": "arn:aws:iam::${AWS::AccountId}:role/admin"
  },
  "Sid": "CloudWatchAndOtherIAMTasks"
}
```
