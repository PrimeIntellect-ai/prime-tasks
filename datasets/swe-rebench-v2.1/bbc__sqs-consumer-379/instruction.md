Allow the option `visibilityTimeout` to be configured after initialisation
## Problem

As suggested in the discussion here:

https://github.com/bbc/sqs-consumer/discussions/369

It would be good to allow users to configure the option `visibilityTimeout` after the consumer has started, this will allow users to change the timeout depending on external factors, such as the runtime configuration.

## Solution

A new method should be added (possibly something along the lines of `changeVisibilityTimeout` that will allow the user to provide a new timeout.

The method should verify the provided timeout and then change the option.

It would be good to add a new emitter as well for option changed, users can then listen to this.

We are open to PRs for this change :)

### Additional contract requirements

- Add a public method `updateOption(option, value)` on the `Consumer` class that updates a mutable consumer option after the instance has been created.
- The only supported option is the string `'visibilityTimeout'`.
- On a successful update the consumer emits an `option_updated` event.
- `updateOption` throws an `Error` if the option is unknown, if the value is not a number, or if the value is not greater than the configured `heartbeatInterval`.


- For `updateOption`, use these exact error messages: `visibilityTimeout must be a number` when the value is not a number; `heartbeatInterval must be less than visibilityTimeout.` when the value is not greater than the configured `heartbeatInterval`; and `The update unknown cannot be updated` when the option is `unknown`.
- On success, `option_updated` must be emitted with the updated option name and value as its two arguments.
- Constructor validation must use these exact error messages: `Missing SQS consumer option [ handleMessage or handleMessageBatch ].` when neither handler is provided; `SQS batchSize option must be between 1 and 10.` when `batchSize` is outside that range; and `heartbeatInterval must be less than visibilityTimeout.` when the required visibility timeout is missing or the heartbeat interval is not less than it.
