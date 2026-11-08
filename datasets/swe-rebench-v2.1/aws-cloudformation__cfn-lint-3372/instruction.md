Confusing behaviour with Type: List<Number>
### CloudFormation Lint Version

cfn-lint 1.3.2

### What operating system are you using?

Windows, Ubuntu

### Describe the bug

If you have a `List<Number>` type and give it a single number cfn-lint reports E1019 messages. A single `List<Number>` can produce many E1019 messages depending upon how many times !Sub or !Ref is used in the template.

E.g. from the Reproduction Template
E1019 'A' is not one of ['Topic', 'AWS::AccountId', 'AWS::NoValue', 'AWS::NotificationARNs', 'AWS::Partition', 'AWS::Region', 'AWS::StackId', 'AWS::StackName', 'AWS::URLSuffix']
test.yaml:13:7

E1019 'A' is not one of ['Topic', 'AWS::AccountId', 'AWS::NoValue', 'AWS::NotificationARNs', 'AWS::Partition', 'AWS::Region', 'AWS::StackId', 'AWS::StackName', 'AWS::URLSuffix']
test.yaml:14:7

The AWS documentation https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/parameters-section-structure.html does not specify how to provide a single number to a List<Number> type which may be required in some circumstances to append to the list at a later date. However providing a single number as a string doesn't cause this issue.

### Expected behavior

The expected behaviour would be to have a single error message for each incorrect `List<Number>` type with the correct line rather than multiple messages with the wrong line. Assuming that a single number should be provided as a string.

### Reproduction template

```
---
AWSTemplateFormatVersion: "2010-09-09"
Parameters:
  A:
    Type: String
  B:
    Type: List<Number>
    Default: 20
Resources:
  Topic:
    Type: AWS::SNS::Topic
    Properties:
      DisplayName: !Sub "${A}-text"
      TopicName: !Sub "${A}-text"
```

### Additional contract requirements

- A `List<Number>` (or `CommaDelimitedList`) parameter whose `Default` is a non-string scalar (for example the integer `20`) is valid and is normalised to a single-element list. Such a parameter must not cause the template's other parameters to be discarded.
- Linting the reproduction template above must not emit any E1019 (`Fn::Sub` parameter) errors. The number of E1019 errors must not grow with the number of `!Sub`/`!Ref` usages of unrelated parameters.

- If a `List<Number>` parameter's `Default` is outside its `AllowedValues`, report one validation error at that `Default` line. Uses of unrelated valid parameters through `!Sub` or `!Ref` must not produce E1019 errors.
