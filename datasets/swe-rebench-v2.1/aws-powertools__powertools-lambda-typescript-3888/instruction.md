Bug: AppSync events `onSubscribe` resolver return type should be ignored
### Expected Behavior

When I create an `onSubscribe` handler using the `AppSyncEventsResolver` from the Event Handler utility I should not have to worry about mistakenly breaking subscriptions, if I leave a return statement in the handler.

### Current Behavior

Whenever the `onSubscribe` handler returns something the subscription will fail with this error:

```json
{
  "errorType": "HandlerExecutionError",
  "message": "Unable to process request"
}
```

### Code snippet

```ts
import { Logger, LogLevel } from '@aws-lambda-powertools/logger';
import { AppSyncEventsResolver } from '@aws-lambda-powertools/event-handler/appsync-events';
import type { Context } from 'aws-lambda';

const logger = new Logger({
  serviceName: 'AppSyncEvents',
  logLevel: LogLevel.DEBUG,
});
const app = new AppSyncEventsResolver({ logger });

app.onSubscribe('/foo/*', (event) => {
  logger.debug('New subscription', { channel: event.info.channel.path });

  return true; // this should be ignored
});

export const handler = async (event: unknown, context: Context) =>
  app.resolve(event, context);
```

### Steps to Reproduce

Deploy the code above, and try to subscribe to the `foo/*` channel.

### Possible Solution

Similar to what Powertools for AWS Lambda (Python) does [here](https://github.com/aws-powertools/powertools-lambda-python/blob/a34e2b9c9fec3ddd88601996d4cee31a0f34dbcb/aws_lambda_powertools/event_handler/events_appsync/appsync_events.py#L157), we should ignore the return of the `onSubscribe` handler.

### Powertools for AWS Lambda (TypeScript) version

latest

### AWS Lambda function runtime

22.x

### Packaging format used

npm

### Execution logs

```Shell

```
