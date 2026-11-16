APIError message fields may be a array
```
{
  "error": {
    "message": [
      "Invalid schema for function 'xxx': In context=(), object schema missing properties"
    ],
    "type": "invalid_request_error",
    "param": null,
    "code": null
  }
}
```

### Additional contract requirements

- When the `message` field is an array of strings, its elements must be joined with `, ` in `APIError.Message`.
- When the `message` field is null, unmarshalling must succeed and leave `APIError.Message` empty.
