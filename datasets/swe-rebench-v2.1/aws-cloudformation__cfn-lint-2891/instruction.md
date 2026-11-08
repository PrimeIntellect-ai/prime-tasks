E2520 false positive for CloudWatch Alarm with expression
### CloudFormation Lint Version

0.80.3

### What operating system are you using?

MacOS

### Describe the bug

A valid CloudWatch alarm that uses a metrics expression is resulting in an E2520 false positive.  The alarm was defined in the CloudWatch console and exported via the "View Source | CloudFormation YAML" capability, so it's definitionally a valid CloudWatch alarm.  To confirm that the bug isn't in the console, created a copy of the alarm using the generated definition and neither CloudFormation nor CloudWatch have any complaints.

### Expected behavior

E2520 should not be raised when `Dimensions` is present under `MetricStat.Metric`.

### Reproduction template

```yaml
AWSTemplateFormatVersion: "2010-09-09"

Description: AXIS ALB alarms

Parameters:
  pLoadBalancerId:
    Type: String
    Default: app/private-api-proxy/ced2a65499b104e7

  pAlarmPrefix:
    Type: String
    Default: MySampleApp

Resources:
  rAlb5xxPercentage:
    Type: AWS::CloudWatch::Alarm
    Properties:
        AlarmName: !Sub "${pAlarmPrefix}-ALB-5XX-Percentage"
        AlarmDescription: >-
            This alarm fires when the ALB is returning HTTP 5XX errors.  It is
            usually due to a misconfiguration of the ALB or not having any
            associated targets.


            See [runbook](https://google.com) for more details.
        ActionsEnabled: true
        OKActions: []
        AlarmActions: []
        InsufficientDataActions: []
        Dimensions: []
        EvaluationPeriods: 15
        DatapointsToAlarm: 3
        Threshold: 5
        ComparisonOperator: GreaterThanOrEqualToThreshold
        TreatMissingData: notBreaching
        Metrics:
          - Id: e1
            Label: ALB 5XX Percentage
            ReturnData: true
            Expression: (m2/(m1+m2+m3+0.001))*100
          - Id: m1
            ReturnData: false
            MetricStat:
              Metric:
                Namespace: AWS/ApplicationELB
                MetricName: RequestCount
                Dimensions:
                  - Name: LoadBalancer
                    Value: !Ref pLoadBalancerId
              Period: 60
              Stat: Sum
          - Id: m2
            ReturnData: false
            MetricStat:
              Metric:
                Namespace: AWS/ApplicationELB
                MetricName: HTTPCode_ELB_5XX_Count
                Dimensions:
                  - Name: LoadBalancer
                    Value: !Ref pLoadBalancerId
              Period: 60
              Stat: Sum
          - Id: m3
            ReturnData: false
            MetricStat:
              Metric:
                Namespace: AWS/ApplicationELB
                MetricName: HTTPCode_ELB_4XX_Count
                Dimensions:
                  - Name: LoadBalancer
                    Value: !Ref pLoadBalancerId
              Period: 60
              Stat: Sum
```
