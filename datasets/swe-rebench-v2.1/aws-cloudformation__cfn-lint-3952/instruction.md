SQS Queue and attached DLQ should have same type
### CloudFormation Lint Version

0.79.7

### What operating system are you using?

MacOS

### Describe the bug

When creating an SQS queue of FIFO type, the attached DLQ to this should also be a FIFO one, the linter does not flag this as an error

### Expected behavior

When creating an SQS queue of FIFO type, the attached DLQ to this queue should be marked as invalid resource if it's not a FIFO queue

### Reproduction template

```yaml
Resources:
  MyDLQ:
    Type: AWS::SQS::Queue
    Properties:
      QueueName: MyDLQNameHere
      # FifoQueue: true
      ContentBasedDeduplication: true
      VisibilityTimeout: 1800
      MessageRetentionPeriod: 1209600

  MyQueue:
    Type: AWS::SQS::Queue
    Properties:
      QueueName: MyQueueNameHere.fifo
      FifoQueue: true
      ContentBasedDeduplication: true
      VisibilityTimeout: 1800
      MessageRetentionPeriod: 7200
      RedrivePolicy:
        deadLetterTargetArn: !GetAtt MyDLQ.Arn
        maxReceiveCount: 2

```

### Additional contract requirements

- Provide a public class `QueueDLQ` in the module `cfnlint.rules.resources.sqs.QueueDLQ`. Its `validate(self, validator, _, instance, schema)` method accepts the validation context, an unused keyword argument, the queue's property map and the property schema, and returns an iterable of validation errors. When the queue's `FifoQueue` setting and the type of the queue referenced by `RedrivePolicy.deadLetterTargetArn` differ, it reports a validation error.
