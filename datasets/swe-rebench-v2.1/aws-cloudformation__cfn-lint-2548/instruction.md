E3002 false positives with intrinsics returning complex types
### CloudFormation Lint Version

0.72.5

### What operating system are you using?

Linux (Fedora)

### Describe the bug

When using intrinsic functions to retrieve complex (ie structured) data from custom resources for other resources E3002 incorrectly marks the intrinsic as invalid properties of the resource.

For example, given a custom resource which returns an AWS::Lambda::Function _Code_ object:
```
"Code": {
   "S3Bucket": "<name>",
   "S3Key": "<object-key>",
   "S3ObjectVersion": "<object-version>"
}
```

Then referencing this as the Code: property of another AWS::Lambda::Function, eg
``` Code: !GetAtt CustomResource.Output.Code ```

cfn-lint raises an E3002 of the form:
```E3002 Invalid Property Resources/Helper/Properties/Code/Fn::GetAtt```

This can be suppressed in the resource's Metadata, but only by suppressing all E3002 errors for that resource, where other instances of the error could be legitimate.    While I imagine that the vast majority of values returned from custom resources are scalars, they are no required to be, and therefore can provide structure as well as values.  Certainly at least in the specific case described here the various Code.<Name> attributes are all correctly referenced when actually running the template.


### Expected behavior

E3002 Should not be raised when an intrinsic is used to return information for a valid partial attribute path.
Since scalars are the most common return values it may be a reasonable compromise to raise a context specific W or I code
At the very least even if metadata annotation is required to suppress this case it should be a unique code, which can be supressed without also supressing common errors such as attribute name typos

### Reproduction template

```yaml
Parameters:
    RoleArn:
        Type: String
    FunctionArn:
        Type: String

Resources:

    GetCodeForLatestS3Object:
        Type: Custom::LambdaSource
        Properties:
            ServiceToken: !Ref FunctionArn
            S3Url: "s3://some-bucket/lambdazips/helper.zip"

    Helper:
        Type: 'AWS::Lambda::Function'
        Properties:
            Handler: 'helper.lambda_handler'
            Role: !Ref RoleArn
            Code: !GetAtt GetCodeForLatestS3Object.Code
```
