[Bug]: Latest addition of QueueMetadata to `error` event is a breaking change
### Describe the bug

In https://github.com/bbc/sqs-consumer/pull/560 QueueMetadata was added as the last param to all event types. In the case of event `error` this is a breaking change because this event has an optional param `message`. From the [Docs](https://bbc.github.io/sqs-consumer/interfaces/Events.html#error):

> Fired when an error occurs interacting with the queue.
If the error correlates to a message, that message is included in Params

For example my `error` event listener looks like this:
```javascript
consumer.addListener('error', (error, message) => {
  // Do something with 'error'

  if (message) {
    // Do something with 'message'
  }
});
```

Which doesn't work anymore because when `message` doesn't exist the second param will get the value of `QueueMetadata` so I'll have to change it to something less stable like this:
```javascript
consumer.addListener('error', (error, message, metadata) => {
  // Do something with 'error'

  if (metadata === undefined) {
    metadata = message;
    message = undefined;
  }

  if (message) {
     // Do something with 'message'
   }
});
```

### Your minimal, reproducible example

in description

### Steps to reproduce

in description

### Expected behavior

always return the same number of arguments `(error, message, metadata)` where message can be undefined

### How often does this bug happen?

Every time

### Screenshots or Videos

_No response_

### Platform

macOS
node22

### Package version

v11.5.0

### AWS SDK version

_No response_

### Additional context

_No response_
