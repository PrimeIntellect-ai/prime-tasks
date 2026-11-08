typo not being caught in Stack Parameters
### CloudFormation Lint Version

0.67.0

### What operating system are you using?

WSL2

### Describe the bug

Type is not getting caught inside stack parameters:

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Typo not caught by cfn-lint'

Parameters:
  WakandaBucket:
    Type: String
    Description: Something.

Resources:
  WakandaStack:
    Type: AWS::CloudFormation::Stack
    Properties:
      TemplateURL: "https://somewhere/foo.yaml"
      Parameters:
        Foobar: !Red WakandaBucket

  Wakanda4EverBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Ref WakandaBucket
```

>Note that after Foobar comes `!Red` insead of `!Ref`.

cfn-lint output for above template is empty, exitcode 0.

When I change the BucketName !Ref to !Red, that one gives me a proper error. But not for the Stack Parameters.

### Expected behavior

I expect something like `Property X/Y/Z has an illegal function Fn::Red`

### Reproduction template

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Typo not caught by cfn-lint'

Parameters:
  WakandaBucket:
    Type: String
    Description: Something.

Resources:
  WakandaStack:
    Type: AWS::CloudFormation::Stack
    Properties:
      TemplateURL: "https://somewhere/foo.yaml"
      Parameters:
        Foobar: !Red WakandaBucket

  Wakanda4EverBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Ref WakandaBucket
```

### Additional contract requirements

- The rule that reports these invalid functions is `E3012` (`ValuePrimitiveType`), in module `cfnlint.rules.resources.properties.ValuePrimitiveType`.
- The rule exposes a public method `check_value(value_map, property_path, primitive_type=..., item_type=...)` that validates a map value against a scalar primitive type and returns a list of `RuleMatch` objects. The returned list is empty when the value conforms.
- For an invalid map value whose primitive type is `Boolean`, the returned `RuleMatch` message must be exactly:
  `Use a valid function [Fn::Base64, Fn::Cidr, Fn::Contains, Fn::FindInMap, Fn::GetAtt, Fn::If, Fn::ImportValue, Fn::Join, Fn::Length, Fn::Select, Fn::Sub, Fn::ToJsonString, Ref] when providing a value of type [Boolean]`
- For an invalid map value whose primitive type is `String`, the returned `RuleMatch` message must be exactly the same text with `[String]` in place of `[Boolean]`.
