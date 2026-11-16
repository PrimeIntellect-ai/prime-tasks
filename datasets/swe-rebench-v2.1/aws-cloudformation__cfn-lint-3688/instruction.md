AWS::Events::Rule should allow both ['EventPattern', 'ScheduleExpression'] and should not throw an E3014
### CloudFormation Lint Version

1.12.4

### What operating system are you using?

ubnutu

### Describe the bug

a resource definition for AWS::Events::Rule which contains both ['EventPattern', 'ScheduleExpression'] deploys just fine and without issue in AWS and therefore, an E3014 should not be thrown by cfn-lint.

This E3014 exception was introduced via https://github.com/aws-cloudformation/cfn-lint/blob/7b0ad9795df5f9a49a585b6c2368a476c286c217/src/cfnlint/data/schemas/patches/extensions/all/aws_events_rule/manual.json

### Expected behavior

do not throw an E3014 if both ['EventPattern', 'ScheduleExpression'] are present in AWS::Events::Rule

### Reproduction template

UpdateRule:
    Type: AWS::Events::Rule
    Properties:
      Description: 'Rule to trigger subscription filter manager lambda on SSM parameter update events'
      EventPattern:
        source: ["aws.ssm"]
        detail-type: ["Parameter Store Change"]
        detail:
          name:
            - "include"
            - "exclude"
            - "disabled"
          operation:
            - "Create"
            - "Update"
            - "Delete"
        account: [!Sub "${AWS::AccountId}"]
      ScheduleExpression: rate(5 minutes)
      Targets:
        - Arn: ARN1
          Id: LAMBDA1

### Additional contract requirements

- The cfn-lint JSON-schema validator supports a `requiredOr` keyword whose value is a list of property names. When the instance is an object and none of the listed properties are present, validation reports the error message `One of ['foo', 'bar'] is a required property` for a keyword value of `['foo', 'bar']`. When at least one listed property is present, or when the instance is not an object, validation passes.
- An `AWS::Events::Rule` resource that specifies both `EventPattern` and `ScheduleExpression` must not report error `E3014`.
