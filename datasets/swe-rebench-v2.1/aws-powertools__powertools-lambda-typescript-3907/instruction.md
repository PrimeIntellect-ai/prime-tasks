Feature request: AppSync Event schema/envelope
### Use case

I'm starting with Appsync events, but the lambda that is called as data source (on publish/subscribe) also receives input from other sources.

Therefore, I want to filter within the lambda event handler from which service the event came from to check which message processor is required. The current new AppSync Events event headers examples contain only the `app.resolve(event, context)` but I would like to place a filter in advance like "if event === appsyncevent". I do not see Validation schema/envelope for these appsync events. I could make one myself, but I think it would be a great addition to this package.

### Solution/User Experience

A validator that can verify if an incoming message is a AppSync Events event, for use cases where multiple sources/services call the same lambda.

### Alternative solutions

```Markdown

```

### Acknowledgment

- [x] This feature request meets [Powertools for AWS Lambda (TypeScript) Tenets](https://docs.powertools.aws.dev/lambda/typescript/latest/#tenets)
- [x] Should this be considered in other Powertools for AWS Lambda languages? i.e. [Python](https://github.com/aws-powertools/powertools-lambda-python/), [Java](https://github.com/aws-powertools/powertools-lambda-java/), and [.NET](https://github.com/aws-powertools/powertools-lambda-dotnet/)

### Future readers

Please react with 👍 and your use case to help us understand customer demand.

### Additional contract requirements

The AppSync Events envelope has these required top-level fields: `identity`, `result`, `request`, `info`, `error`, `prev`, `stash`, `outErrors`, and `events`. `identity` is null or a supported AppSync identity; `result`, `error`, and `prev` are null; `request` contains a nullable `domainName` and may contain a string-to-string `headers` map; `info` contains a `channel` with a string `path` and string-array `segments`, a `channelNamespace` with a string `name`, and an operation. `stash` is an object and `outErrors` is an array.

A publish envelope has operation `PUBLISH` and a non-empty `events` array. Every event entry has a string `id` and an object `payload` whose keys are strings and whose values may be any JSON values. A subscribe envelope has operation `SUBSCRIBE` and `events` is null. Each operation-specific validator accepts its corresponding well-formed envelope and rejects malformed envelopes and envelopes for the other operation.
