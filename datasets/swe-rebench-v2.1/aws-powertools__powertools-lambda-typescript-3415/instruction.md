Bug: SnsSchema parsing fails when `Subject` is null
### Expected Behavior

Sns events with a `Subject` that is null should pass schema parsing with `SnsSchema`.

### Current Behavior

For an event like this:
```json
{
  "Records": [
    {
      "EventSource": "aws:sns",
      "EventVersion": "1.0",
      "EventSubscriptionArn": "a subscription arn",
      "Sns": {
        "Type": "Notification",
        "MessageId": "a message id",
        "TopicArn": "an arn",
        "Subject": null,
        "Message": "hi there",
        "Timestamp": "2024-12-04T08:00:04.497Z",
        "SignatureVersion": "1",
        "Signature": "",
        "SigningCertUrl": "http://www.google.com",
        "UnsubscribeUrl": "http://www.google.com",
        "MessageAttributes": {}
      }
    }
  ]
}
```

The following fails:
```typescript
import { SnsSchema } from '@aws-lambda-powertools/parser/schemas';

SnsSchema.parse(event)
```

This is due to `Subject` being null. It can be omitted or undefined, but in the case of null it seems to throw. However, it is a valid case for SNS to have `Subject` be null.

### Code snippet

```typescript
import { SnsSchema } from '@aws-lambda-powertools/parser/schemas';

SnsSchema.parse(
{
  "Records": [
    {
      "EventSource": "aws:sns",
      "EventVersion": "1.0",
      "EventSubscriptionArn": "a subscription arn",
      "Sns": {
        "Type": "Notification",
        "MessageId": "a message id",
        "TopicArn": "an arn",
        "Subject": null,
        "Message": "hi there",
        "Timestamp": "2024-12-04T08:00:04.497Z",
        "SignatureVersion": "1",
        "Signature": "",
        "SigningCertUrl": "http://www.google.com",
        "UnsubscribeUrl": "http://www.google.com",
        "MessageAttributes": {}
      }
    }
  ]
}
)

```

### Steps to Reproduce

Run the codesnippet above and it should fail

### Possible Solution

Allow the `Subject` field to be null as well as omitted

### Powertools for AWS Lambda (TypeScript) version

latest

### AWS Lambda function runtime

22.x

### Packaging format used

npm

### Execution logs

```Shell

```
