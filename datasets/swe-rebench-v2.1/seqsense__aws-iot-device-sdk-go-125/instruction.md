ThingShadow: use ClientToken
Request and response can be associated by ClientToken.
`Report`/`Desire`/`Delete` should return error when rejected.

Ref: https://github.com/seqsense/aws-iot-device-sdk-go/pull/121

### Spec
- Request: https://docs.aws.amazon.com/iot/latest/developerguide/device-shadow-document.html#device-shadow-example-request-json
- Error response: https://docs.aws.amazon.com/iot/latest/developerguide/device-shadow-document.html#device-shadow-example-error-json

### Additional contract requirements

- The client token is carried in the JSON field `clientToken` of both the request and the response.
- A response whose `clientToken` does not match the pending request is ignored (the request keeps waiting for its matching response).
- A received message that cannot be parsed is reported to the handler registered with `OnError`.
