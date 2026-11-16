AWS::Events::Rule ScheduleExpression: "cron(* 1 * * * *)"
*cfn-lint version: (cfn-lint 0.27.5)*

*Description of issue.*

```
  EventRule:
    Type: "AWS::Events::Rule"
    Properties:
      ScheduleExpression: "cron(* 1 * * * *)"
      State: "ENABLED"
      Targets:
        - Arn: !Ref Foo
          Id: "Foo"
          RoleArn: !GetAtt FooArn.Arn
```

Check should be probably in:

[src/cfnlint/rules/resources/events/RuleScheduleExpression.py](https://github.com/aws-cloudformation/cfn-python-lint/blob/master/src/cfnlint/rules/resources/events/RuleScheduleExpression.py)

The above `ScheduleExpression` is invalid (need a value for minute if hour is set). For example `cron(0 1 * * ? *)`

---

[Schedule Expressions for Rules documentation](https://docs.aws.amazon.com/eventbridge/latest/userguide/scheduled-events.html)

### Additional contract requirements

- A cron schedule expression must not specify values in both the Day-of-month and Day-of-week fields; at least one of those two fields must be `?`. For example `cron(0 1 * * * *)` is invalid, while `cron(0 1 * * ? *)` is valid.
