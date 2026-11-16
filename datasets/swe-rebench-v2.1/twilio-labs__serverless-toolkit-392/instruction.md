Content-Type header check in response is not handling charset
Broken:

```js
exports.handler = async (context, event, callback) => {
  const response = new Twilio.Response();
  response.appendHeader('Content-Type', 'application/json; charset=UTF-8');
  response.setStatusCode(400);
  response.setBody(
    {message: 'I am a JSON message'}
  )
  return callback(null, response);
};
```

Working:
```js
exports.handler = async (context, event, callback) => {
  const response = new Twilio.Response();
  response.appendHeader('Content-Type', 'application/json');
  response.setStatusCode(400);
  response.setBody(
    {message: 'I am a JSON message'}
  )
  return callback(null, response);
};
```

Instead we should adjust the check for the `Content-Type` header to validate that it includes `application/json` as opposed to being explicitly `application-json`.

https://github.com/twilio-labs/serverless-toolkit/blob/33ca348aa7886cdf58255900077b156f00461433/packages/runtime-handler/src/dev-runtime/internal/response.ts#L139
