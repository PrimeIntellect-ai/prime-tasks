Actual Payload Shared in Step Functions Console On Function Error
# Problem

I want to use AWS Lambda Power Tuning to invoke Lambda functions with an input payload that contains credentials. I do not want this information in the AWS Step Functions execution history.

Initially I explored the use of a pre-processor to workaround this by allowing the pre-processor to fetch credentials and pass those direct to the Lambda being tuned. This I understand would all execute within a single state of the Step Functions, so credentials would not be shared in the Step Functions console.

However, if the Lambda being tuned throws an error, we [log the payload](https://github.com/alexcasalboni/aws-lambda-power-tuning/blob/4d0d35d0410550574d23931d3cc13a0e32dabd0e/lambda/executor.js#L162C110-L162C142), which in my case would include the credentials.

# Proposed Solutions

Two ideas spring to mind, but I'm open to discussing the problem further and open to other suggestions how to solve this:

1. we stop including the payload in the error message thrown. The payload I think should be the same for each execution of the Step Functions, unless we use a pre-processor which returns different output given the same input. So is logging the payload valuable?

2. we introduce a new toggle to enable / disable inclusion of the payload in the error thrown, defaulting to showing the payload to maintain consistent behaviour, but this would allow users like me to disable it if desired.

# Contributing

I'm happy to contribute to this project with any agreed changes.

### Additional contract requirements

The executor input supports `disablePayloadLogs: true` to suppress the payload sent to the tuned Lambda from invocation-failure errors exposed in Step Functions execution history. This applies both to the original input payload and to any payload produced by a pre-processor.
