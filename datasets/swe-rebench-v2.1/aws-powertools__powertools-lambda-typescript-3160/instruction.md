Feature request: Support Sequential Async Processing of Records for SqsFifoPartialProcessor
### Use case

I am working with a FIFO SQS queue that requires processing batch records in an asynchronous manner. However, to maintain the order of messages, the `SqsFifoPartialProcessor` currently only supports sequential **synchronous** processing. This limitation prevents me from using **asynchronous** processing in my FIFO queue handler, which is essential for my use case.

### Solution/User Experience

I propose enhancing the `SqsFifoPartialProcessor` to support **sequential asynchronous** processing while maintaining message ordering. This approach would be similar to the solution implemented [here](https://github.com/aws-powertools/powertools-lambda-typescript/commit/e31279af90446050a7974fbe25c34758f64915f9), but tailored to work with the `SqsFifoPartialProcessor`. This would allow users to leverage asynchronous processing within FIFO queues without sacrificing the ordering guarantees.

### Alternative solutions

_No response_

### Acknowledgment

- [X] This feature request meets [Powertools for AWS Lambda (TypeScript) Tenets](https://docs.powertools.aws.dev/lambda/typescript/latest/#tenets)
- [X] Should this be considered in other Powertools for AWS Lambda languages? i.e. [Python](https://github.com/aws-powertools/powertools-lambda-python/), [Java](https://github.com/aws-powertools/powertools-lambda-java/), and [.NET](https://github.com/aws-powertools/powertools-lambda-dotnet/)

### Future readers

Please react with 👍 and your use case to help us understand customer demand.

### Additional contract requirements

- Add a public class `SqsFifoPartialProcessorAsync`, exported from `@aws-lambda-powertools/batch`, that processes SQS FIFO records sequentially and asynchronously while preserving message order. It is used with the existing `processPartialResponse` function in an asynchronous Lambda handler, which returns a partial-failure response listing the failed records in `batchItemFailures`.
- The `skipGroupOnError` option is supported for both `SqsFifoPartialProcessor` and `SqsFifoPartialProcessorAsync`. When `true`, after a record in a message group fails, the remaining records of that group are reported as failed and processing continues with the next message group. When `false` (the default), processing stops at the first failure and all remaining records are reported as failed.
