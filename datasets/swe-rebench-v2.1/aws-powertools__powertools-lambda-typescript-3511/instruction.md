Bug: API Gateway envelopes assumes message body is always a JSON
### Expected Behavior

When working with the `ApiGatewayEnvelope` and `ApiGatewayV2Envelope` I should be able to extract the message body regardless of whether it's a plain text string, base64-encoded string, or a JSON-stringified one.

### Current Behavior

When the message body is not a JSON-stringified object the envelope throws a runtime error as it's unable to parse it with `JSON.parse()`.

### Code snippet

```ts
import { z } from 'zod';
import { ApiGatewayEnvelope } from '@aws-lambda-powertools/parser/envelopes';

export const handler = async (event) => {
  try {
    ApiGatewayEnvelope.parse(event, z.string());
  } catch (error) {
    console.error(error);
  }
}
```

### Steps to Reproduce

Send a request with a body that is either plain text or an encoded binary.

### Possible Solution

_No response_

### Powertools for AWS Lambda (TypeScript) version

latest

### AWS Lambda function runtime

22.x

### Packaging format used

npm

### Execution logs

```Shell

```

### Additional contract requirements

- On schema-validation failure, `parse` must throw a `ParseError` whose message contains `Failed to parse API Gateway body` for `ApiGatewayEnvelope` or `Failed to parse API Gateway HTTP body` for `ApiGatewayV2Envelope`, with a `ZodError` as its cause. A null REST body must produce the issue `{ code: 'invalid_type', expected: 'object', received: 'null', path: ['body'], message: 'Expected object, received null' }`; an undefined HTTP (v2) body must produce `{ code: 'invalid_type', expected: 'object', received: 'undefined', path: ['body'], message: 'Required' }`. For `safeParse`, an invalid REST event missing `path` with a null body must return `success: false`, an error with the REST message and a cause containing the `path` issue `{ code: 'invalid_type', expected: 'string', received: 'undefined', path: ['path'], message: 'Required' }` followed by the null-body issue above, and `originalEvent` equal to the input. An invalid HTTP (v2) event missing `rawPath` with an undefined body must return `success: false`, an error with the HTTP message and a cause containing the `rawPath` issue `{ code: 'invalid_type', expected: 'string', received: 'undefined', path: ['rawPath'], message: 'Required' }` followed by the undefined-body issue above, and `originalEvent` equal to the input.
