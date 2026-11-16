Convert a string containing JSON to JSON object
Hi,

Is there a way to change the following string field `special` to a JSON object? I can do this in Javascript of course but was wondering if there's a way to do it using jsonata.

Input data:
```
{
  "special": "{\"field1\":\"abc\",\"field2\":321}"
}
```

Expected output:
```
{
  "special": {
    "field1": "abc",
    "field2": 321
  }
}
```

Thanks!

### Additional contract requirements

- Add a public function `$eval(expression: string, focus?: any)` that parses and evaluates `expression` as a JSONata expression. When `focus` is supplied it is used as the input data for the evaluation; otherwise the current context input is used.
- If the `expression` argument is `undefined`, `$eval` returns `undefined`.
- If `expression` cannot be parsed, `$eval` throws a JSONata error with code `D3120`.
- If `expression` is parsed successfully but an error occurs during evaluation, `$eval` throws a JSONata error with code `D3121`.
