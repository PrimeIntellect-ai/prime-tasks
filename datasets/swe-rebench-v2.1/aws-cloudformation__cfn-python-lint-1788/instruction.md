E1029 - False positive with multiline YAML string
*cfn-lint version: (`cfn-lint --version`)*
0.35.0

*Description of issue.*
Using ${iot:Connection.Thing.ThingName} inside an AWS::IoT::Policy PolicyDocument is flagged as an embedded parameter outside of Fn::Sub.

Freshly installed cfn-lint this morning. I'm using Python 2.7 and VS Code

* Sample Template:
```
AWSTemplateFormatVersion: '2010-09-09'

Resources:
  TestPolicy:
    Type: AWS::IoT::Policy
    Properties:
      PolicyDocument: >
        {
          "Version": "2012-10-17",
          "Statement": [
            {
              "Effect": "Allow",
              "Action": "iot:Connect",
              "Resource": "arn:aws:iot:eu-central-1:123456789012:client/${iot:Connection.Thing.ThingName}"
            }
          ]
        }
      PolicyName: ConnectWithThingName
```

In the second example in their developer guide on AWS IoT they use the exact same policy document. https://docs.aws.amazon.com/iot/latest/developerguide/connect-policy.html

* Feature request:
Like with IAM policies, IoT policies shouldn't have variables flagged as embedded parameters.
