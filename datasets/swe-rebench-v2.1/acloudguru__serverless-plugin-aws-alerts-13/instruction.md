Alarm won't trigger even alarm was created successfully
Currently, alarm has invalid dimension. so alarm won't trigger even alarm was created successfully.

This is our example serverless.yml:
```yml
# (truncated)

plugins:
  - serverless-plugin-aws-alerts
functions:
  hello:
    handler: handlers.hello
    alarms:
      - functionErrors

custom:
  alerts:
    definitions:
      functionErrors:
        namespace: 'AWS/Lambda'
        metric: Errors
        threshold: 1
        statistic: Minimum
        period: 600
        evaluationPeriods: 1
        comparisonOperator: GreaterThanThreshold

# (truncated)
```


Generated CloudFormation content:
```json
{
  "Resources": {
    "ValidateFunctionErrorsAlarm": {
      "Type": "AWS::CloudWatch::Alarm",
      "Properties": {
        "Namespace": "AWS/Lambda",
        "MetricName": "Errors",
        "Threshold": 1,
        "Statistic": "Minimum",
        "Period": 600,
        "EvaluationPeriods": 1,
        "ComparisonOperator": "GreaterThanThreshold",
        "OKActions": [],
        "AlarmActions": [],
        "InsufficientDataActions": [],
        "Dimensions": [
          {
            "Name": "HelloLambdaFunctionName",
            "Value": {
              "Ref": "HelloLambdaFunction"
            }
          }
        ]
      }
    }
  }
}
```

I think value of `Dimensions[0].Name` should be use 'FunctionName', not `${ref}Name`.
