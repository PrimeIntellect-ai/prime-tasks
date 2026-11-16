APIError.error.code type error!!!
error, json: cannot unmarshal number into Go struct field APIError.error.code of type string

### Additional contract requirements

- The exported `APIError` type in package `openai` must expose a field `Code` of type `any` that holds the `code` value of an API error response.
- Unmarshalling an API error JSON object into an `APIError` must succeed when the `code` field is a JSON integer, a JSON string, or absent.
- When the `code` field is a JSON integer-form number within the range of Go `int`, `Code` must hold it as a Go `int`.
- When the `code` field is a JSON string, `Code` must hold it as a Go `string`.
- When a newly declared `APIError` is unmarshalled from a JSON object without a `code` field, `Code` must be `nil`.
- The `param` field is optional; when a newly declared `APIError` is unmarshalled from a JSON object without a `param` field, `Param` must be `nil`.
- Unmarshalling must return an error when the JSON is malformed, or when the `message`, `type`, or `param` field is present with a value that is not a string.
