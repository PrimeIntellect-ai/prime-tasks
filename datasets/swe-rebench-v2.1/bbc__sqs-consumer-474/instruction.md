[Bug]: CredentialsProviderError is not treated as a connection error
### Describe the bug

The [HIDDEN] function does not account for the `CredentialsProviderError` which can be [thrown by the AWS SDK for JavaScript v3](https://github.com/search?q=repo%3Aaws%2Faws-sdk-js-v3+CredentialsProviderError&type=code).

Failure to handle this error means the default [pollingWaitTimeMs](https://github.com/bbc/sqs-consumer/blob/main/src/consumer.ts#L82) of 0ms will be used, instead of the 10,000ms [authenticationErrorTimeout](https://github.com/bbc/sqs-consumer/blob/main/src/consumer.ts#L80-L81), producing a high volume of errors if there is an IAM misconfiguration or failure.

### Your minimal, reproducible example

N/A

### Steps to reproduce

1. Pass invalid IAM configuration
2. Receive messages

### Expected behavior

Delay of 10s applies

### How often does this bug happen?

Every time

### Screenshots or Videos

_No response_

### Platform

macOS, Linux

### Package version

v9.0.0

### AWS SDK version

v3

### Additional context

_No response_

### Additional contract requirements

- When polling fails with an AWS SDK for JavaScript v3 `CredentialsProviderError`, wait for the 10,000 ms authentication-error timeout before polling again instead of using the default polling wait time.
