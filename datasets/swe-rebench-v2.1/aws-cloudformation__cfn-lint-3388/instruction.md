v1: E2001 'AllowedPattern' is not one of [ ... ] for parameter type AWS::EC2::Image::Id
### CloudFormation Lint Version

1.3.3

### What operating system are you using?

Ubuntu

### Describe the bug

Validation fails when specifying the `AllowedPattern` propety for a parameter with type `AWS::EC2::Image::Id`.

### Expected behavior

Validation should pass.

### Reproduction template

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Parameters:
  MyImageId:
    Type: AWS::EC2::Image::Id
    AllowedPattern: '^ami-[0-9a-f]+$'
Resources:
  myInstance:
    Type: AWS::EC2::Instance
    Properties:
      ImageId: !Ref MyImageId
```
