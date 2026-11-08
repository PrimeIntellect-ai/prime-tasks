[Bug]: When consumer fails to react to SQS instant retry occurs
### Describe the bug

If the consumer cannot connect to SQS due to no internet connection or the unlikely event SQS is down, if pollingWaitTimeMs is 0 (set by default), it will instantly retry the connection causing a continual flurry of requests. There is currently no option to resolve this other than by setting pollingWaitTimeMs to a higher value however this also isn't ideal since it adds a longer wait between polls too. Currently authentication errors are caught and can have a back-off configured with authenticationErrorTimeout though this doesn't exist for general connection errors.

### Your minimal, reproducible example

https://stackblitz.com/github/fraserbenjamin/sqs-consumer-starter?file=index.js

### Steps to reproduce

Once the application starts you will see the console quickly filled up with error messages saying `Could not load credentials from any providers`, although if you had credentials available it would then say `SQS receive message failed: The specified queue does not exist` and if there was a connectivity issue you would get `SQS receive message failed: getaddrinfo ENOTFOUND sqs.eu-central-1.amazonaws.com`

### Expected behavior

As a user I expected these retries to be throttled after a failure but instead I see requests continuously being made and error messages being sent to the console at an excessive rate.

### How often does this bug happen?

Every time

### Screenshots or Videos

<img width="1085" alt="Screenshot 2024-04-04 at 08 49 41" src="https://github.com/bbc/sqs-consumer/assets/29359940/c87e4a3e-51b3-487e-bd84-8802ace83b69">


### Platform

Occurs on all platforms and tested with the issue happening on Node versions 16-20.

### Package version

9.1.0

### AWS SDK version

3.547.0

### Additional context

_No response_

### Additional contract requirements

- When a connection error pauses retries, emit `logger.debug("authentication_error", { code: <error code or "Unknown" if absent>, detail: "There was an authentication error. Pausing before retrying." })`.
- The following SQS error codes are connection errors that pause retries: `CredentialsError`, `UnknownEndpoint`, `AWS.SimpleQueueService.NonExistentQueue`, `CredentialsProviderError`, `InvalidAddress`, `InvalidSecurity`, `QueueDoesNotExist`, `RequestThrottled`, `OverLimit`. A response with HTTP status code 403 is also a connection error.
- When retries are paused for a connection error, resume polling no later than the configured `authenticationErrorTimeout` after the error.
