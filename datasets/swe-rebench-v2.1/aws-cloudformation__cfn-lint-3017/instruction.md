Doesn't catch invalid `rate(1 hours)`
*cfn-lint version: (`cfn-lint --version`)*

0.44.7

*Description of issue.*

cfn-lint doesn't recognize that this ScheduledExpression is invalid (should be `rate(1 hour)`)
```yaml
  ExampleRule:
    Type: AWS::Events::Rule
    Properties:
      Description: desc
      Name: name
      ScheduleExpression: rate(1 hours)
      State: ENABLED
```

But when building the cloudformation, I get the following error:

```
Parameter ScheduleExpression is not valid. (Service: AmazonCloudWatchEvents; Status Code: 400; Error Code: ValidationException; Request ID: ...; Proxy: null)
```

I saw #816, but since this is a `rate` issue, not a `cron` issue, I thought I should open a new ticket

### Additional contract requirements

- Also reject `rate(1 minutes)` and `rate(2 hour)` as invalid ScheduleExpression values.
