v1: E1019 Exception 'maximum recursion depth exceeded while calling a Python object' raised while validating 'enum' when 'Ref' is resolved when ... whe 'Ref' is resolved
### CloudFormation Lint Version

v1.3.0

### What operating system are you using?

Ubuntu

### Describe the bug

This is more trick if its a bug, AWS do understand it and does it correct though.

AWS figure out that it inner !Ref should not use the name in !Sub but the rest in the template but as they are the same the Sub named variable is not needed.
```yaml
                Resource: !Sub
                  - "arn:aws:s3:::${OutputBucketName}"
                  - OutputBucketName: !Ref OutputBucketName
```

the above is the same as this:
```yaml
                Resource: !Sub "arn:aws:s3:::${OutputBucketName}"
```


### Expected behavior

Expected as AWS do accept that structure and it works correct this should be more of a refactoring recommendation but deferentially not be a run away recursion.

### Reproduction template

```yaml
 ---
AWSTemplateFormatVersion: '2010-09-09'
Description: bug E1019
  IAMRole:
    Type: AWS::IAM::Role
    Properties:
      Description: 'The IAM role'
      Path: '/'
      Policies:
        - PolicyName: 's3-iam-policy'
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Action:
                  - 's3:List*'
                  - 's3:Put*'
                Effect: Allow
                Resource: !Sub
                  - "arn:aws:s3:::${OutputBucketName}"
                  - OutputBucketName: !Ref OutputBucketName
```
