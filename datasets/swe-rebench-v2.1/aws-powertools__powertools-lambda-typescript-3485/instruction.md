Bug: `APIGatewayRequestAuthorizerEventV2Schema` has invalid definition for the `identitySource` field
### Expected Behavior

The `identitySource` field in `APIGatewayRequestAuthorizerEventV2` can be null when the Lambda authorizer is not configured with an identity source (see screenshot from the AWS Console below).

![Image](https://github.com/user-attachments/assets/e5ee6da8-c3fa-4e11-901c-c2e36411fc16)

### Current Behavior

The current definition does not account for this scenario, leading to an error:

https://github.com/aws-powertools/powertools-lambda-typescript/blob/e1bc6c5e324d8e76fdde043d962d9c1c42e8c0c3/packages/parser/src/schemas/apigwv2.ts#L233

![Image](https://github.com/user-attachments/assets/37550be9-4d22-4db5-974e-807c64e920c7)

Even the `@types/aws-lambda` package has invalid type definition:

https://github.com/DefinitelyTyped/DefinitelyTyped/blob/01bf6ea3ae73629f4d488d777df91781e466ba15/types/aws-lambda/trigger/api-gateway-authorizer.d.ts#L38

### Code snippet

```typescript
APIGatewayRequestAuthorizerEventV2Schema.parse(event);
```

### Steps to Reproduce

When creating a Lambda authorizer, do not specify an identity source.

### Possible Solution

[HIDDEN]

### Powertools for AWS Lambda (TypeScript) version

latest

### AWS Lambda function runtime

20.x

### Packaging format used

npm

### Execution logs

```Shell

```
