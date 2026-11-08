Using AWS Pseudo Parameters with SNS Topic declaration
# This is a Bug Report

## Description

I am trying to reference a SNS Topic that already exists using AWS Pseudo Parameters e.g.

```
custom:
  alerts:
    topics:
      alarm:
        topic:
          Fn::Join:
            - ""
            - - "arn:aws:sns:"
              - Ref: "AWS::Region"
              - ":"
              - Ref: "AWS::AccountId"
              - ":CloudWatch-ErrorLogs"
    function:
      - name: SomeAlarm
        description: Some Alarm Description
        metric: SomeMetric
        treatMissingData: notBreaching
        threshold: 0
        statistic: Sum
        period: 60
        evaluationPeriods: 1
        comparisonOperator: GreaterThanThreshold
        pattern: '[ERROR]'
```
However this results in the following error;

>   Type Error ---------------------------------------------
>
>   topic.indexOf is not a function
>
>      For debugging logs, run again after setting the "SLS_DEBUG=*" environment variable.
>
>   Get Support --------------------------------------------
>      Docs:          docs.serverless.com
>      Bugs:          github.com/serverless/serverless/issues
>      Forums:        forum.serverless.com
>      Chat:          gitter.im/serverless/serverless
>
>   Your Environment Information -----------------------------
>      OS:                     linux
>      Node Version:           9.4.0
>      Serverless Version:     1.26.0

Does the plugin not support using AWS Pseudo Parameters or am I just doing something wrong?
Also, I haven't tried it yet but would CloudFormation References work (E.g. ${cf:x.y})?

## Additional Data

I also tried using variable resolution instead, so creating a custom variable which the topic then references;

```
custom:
  sns:
    Fn::Join:
      - ""
      - - "arn:aws:sns:"
        - Ref: "AWS::Region"
        - ":"
        - Ref: "AWS::AccountId"
        - ":CloudWatch-ErrorLogs"
  alerts:
    topics:
      alarm:
        topic: ${self:custom.sns}
```

However that produced the same result.

* ***Serverless Framework Version: 1.26.0***:
