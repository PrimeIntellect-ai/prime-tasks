E1030 error on Fn::Length while comparing with a number using Fn::Equals
### CloudFormation Lint Version

1.5.0

### What operating system are you using?

Mac, Linux

### Describe the bug

I am trying to add a condition where it compare if a CommaDelimitedList parameters had two elements.
```yaml
Conditions:
   TwoVpcConfig: !Equals [ Fn::Length: !Ref VpcCIDRs, 2 ]
```
and I get the following error:
```
[cfn-lint] E1030: {'Fn::Length': {'Ref': 'VpcCIDRs'}} is not of type 'string'
```

However this errors started few days ago with an update of cfn-lint.

AWS Documentation states that Equals should accept any type of value and CommaDelimitedList is actually and array so `Fn::Equals` and `Fn::Length` should not complain.

If I ignore **E1030** from cfn-lint the template deploys correctly with no issue.

### Expected behavior

It should not complain

### Reproduction template

```yaml
AWSTemplateFormatVersion: 2010-09-09
Transform: 'AWS::LanguageExtensions'
...
Parameters:
  VpcCIDRs:
    Type: CommaDelimitedList

Conditions:
   TwoVpcConfig: !Equals [ Fn::Length: !Ref VpcCIDRs, 2 ]
...
```
