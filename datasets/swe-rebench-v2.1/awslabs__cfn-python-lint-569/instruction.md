Can't use lists directly in a Sub.
*cfn-lint version: (`cfn-lint --version`)*

*Description of issue.*
"Template validation error: Template error: variable pValues in Fn::Sub expression does not resolve to a string"

Please provide as much information as possible:
* Template linting issues:
Subs can't be directly included in a Sub
```
---
AWSTemplateFormatVersion: "2010-09-09"
Parameters:
  pKey:
    Type: String
  pValues:
    Type: CommaDelimitedList
Resources:
  MySubscription:
    Type: AWS::SNS::Subscription
    Properties:
      FilterPolicy: !Sub |
        ${pKey}: ${pValues}
```
