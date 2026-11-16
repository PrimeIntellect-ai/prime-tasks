Ability for force JSON parsing
I am communicating with a service that ALWAYS returns `mime-type = 'text/plain'` could the ability to force JSON parsing be added? Something like:

```javascript

options = {
  json: 'force'
}

```

### Additional contract requirements

- `Wreck.get(uri, options, callback)` accepts an `options.json` value:
  - `true` or `'smart'` - parse the response body as JSON only when the response `Content-Type` is `application/json`.
  - `'force'` - attempt to parse the response body as JSON regardless of the response `Content-Type`.
- When JSON parsing is attempted and the body is valid JSON, the callback receives the parsed value as `payload` and no error.
- When JSON parsing is attempted and the body is not valid JSON, the callback receives an `Error` as `err`.
- When JSON parsing is not performed, `payload` is the raw response body; an empty body yields `null`.
