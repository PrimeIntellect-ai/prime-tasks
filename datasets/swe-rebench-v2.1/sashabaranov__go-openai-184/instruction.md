ChatCompletionRequest with stream: true return EOF
When using ChatCompletionRequest and setting `stream: true` to send multiple conversation content, EOF is returned and no error information can be obtained.

### Additional contract requirements

When a streaming chat completion or completion request receives an error payload from the API rather than a stream of `data:` events, the stream's `Recv` method must return an error that carries the API error information (an `*APIError`, returned directly or wrapped) rather than `io.EOF`, so callers can obtain the error details. The error payload is a JSON object with an `error` field that decodes into the API error type.
