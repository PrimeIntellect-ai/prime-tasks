Please provider a option to determine whether do escape or not when log in json format
[HIDDEN]

But, the `escapeHTML` in `json.Encoder` is default to true. So when I want to log some info which will refer these symbol: &, <, and >, the log result is unexpected.

I would like to submit a PR to enhance it.

### Additional contract requirements

- `LoggerOptions` (in package `go-hclog`) must expose a public boolean field named `JSONEscapeDisabled`.
- When a logger is constructed with `JSONFormat: true` and `JSONEscapeDisabled: true`, the JSON log output must leave the characters `&`, `<`, and `>` unescaped, while the message content otherwise remains intact.
- When a logger is constructed with `JSONFormat: true` and `JSONEscapeDisabled` left at its default value of `false`, the JSON log output must retain the existing HTML-escaping behavior for `&`, `<`, and `>`.
