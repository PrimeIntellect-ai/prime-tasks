Environment Variables as Integer on AWS SAM template
*cfn-lint version: 0.28.4*

*Description of issue.*
When using Integer as Envrironment Variable for Serverless (AWS SAM), we get an error saying it should be String.

E3012 Property Resources/MyResource/Properties/Environment/Variables/MAIL_PORT should be of type String


Please provide as much information as possible:
* Template linting issues:
  * Please provide a CloudFormation sample that generated the issue.

```
Description: My Lambda Repository
Transform: AWS::Serverless-2016-10-31

Globals:
  Function:
    Environment:
      Variables:
        MAIL_PORT: 587

Resources:
  MyLambda:
    Type: AWS::Serverless::Function
    Properties:
      FunctionName: my-lambda
      CodeUri: .
      Handler: pipeline.php
      Timeout: 300
      MemorySize: 512
      Environment:
        Variables:
          TENANT_QUEUE: !Ref TenantQueue
      Role: !GetAtt LambdaExecutionRole.Arn
      Layers: [!Sub "arn:aws:lambda:${AWS::Region}:209497400698:layer:php-73:18"]
      Runtime: provided
      VpcConfig:
        SecurityGroupIds: [!ImportValue AllowAllAddressesContainerSecurityGroup]
        SubnetIds: !Split [',', !ImportValue PrivateSubnets]
```

  * If present, please add links to the (official) documentation for clarification.
  * Validate if the issue still exists with the latest version of `cfn-lint` and/or the latest Spec files
* Feature request:
  * Please provide argumentation about the missing feature. Context is key!


Cfn-lint uses the [CloudFormation Resource Specifications](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-resource-specification.html) as the base to do validation. These files are included as part of the application version. Please update to the latest version of `cfn-lint` or update the spec files manually (`cfn-lint -u`)
