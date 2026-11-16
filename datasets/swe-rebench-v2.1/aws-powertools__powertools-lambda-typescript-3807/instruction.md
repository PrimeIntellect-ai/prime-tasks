Feature request: implement APIGatewayProxyWebsocketEventSchema
### Use case

as a Developer I would  to use powertools parser on websocket lambda's event

### Solution/User Experience

implement APIGatewayProxyWebsocketEventSchema

### Alternative solutions

```Markdown

```

### Acknowledgment

- [x] This feature request meets [Powertools for AWS Lambda (TypeScript) Tenets](https://docs.powertools.aws.dev/lambda/typescript/latest/#tenets)
- [ ] Should this be considered in other Powertools for AWS Lambda languages? i.e. [Python](https://github.com/aws-powertools/powertools-lambda-python/), [Java](https://github.com/aws-powertools/powertools-lambda-java/), and [.NET](https://github.com/aws-powertools/powertools-lambda-dotnet/)

### Future readers

Please react with 👍 and your use case to help us understand customer demand.

### Additional contract requirements

Expose `APIGatewayProxyWebsocketEventSchema` through the parser's public schema exports so consumers can import and use it to validate WebSocket Lambda events.

A valid event has required top-level fields `type` and `methodArn` (strings), `headers` (a string-to-string map), `multiValueHeaders` (a string-to-array-of-strings map), `requestContext` (an object described below), and `isBase64Encoded` (a boolean). The request context requires string fields `routeKey`, `extendedRequestId`, `requestTime`, `stage`, `requestId`, `domainName`, `connectionId`, and `apiId`; `eventType` must be `CONNECT`, `DISCONNECT`, or `MESSAGE`; `messageDirection` must be `IN` or `OUT`; `connectedAt` and `requestTimeEpoch` must be numbers; and `identity` must contain the string `sourceIp` (with optional string `userAgent`).

`queryStringParameters` and `stageVariables`, when present, are string-to-string maps or null. `multiValueQueryStringParameters`, when present, is a string-to-array-of-strings map or null. `body`, when present, is a string or null. These fields are optional. Invalid required fields or values of the wrong types must be rejected; valid WebSocket event payloads must be accepted.
