Support promises on `validate()`

### Additional contract requirements

A call to `validate()` without a callback, whether made on a Joi schema or through the Joi validation API, returns a result that retains its `error` and `value` properties and supports `then` and `catch` chaining. The promise fulfills with the validated value on success and rejects with the validation error on failure. Exceptions thrown by promise handlers propagate as rejections and can be handled by a subsequent rejection handler.
