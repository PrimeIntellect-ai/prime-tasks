JSON renderer does not render causes
Hello there,

It looks like rendering causes was not implemented for the JSON renderer.

```plaintext
Error: up::error::sql

  × SQL query failed
  ├─▶ error returned from database: operator does not exist: uuid = text
  ╰─▶ operator does not exist: uuid = text
```

Example JSON output:

```json
{"message": "SQL query failed","code": "up::error::sql","severity": "error","labels": [],"related": []}
```

I am not sure if this was an intentional omission, but it would be helpful to provide additional context if it were there, especially in log aggregators.

Cheers!

### Additional contract requirements

- The JSON output must include available error causes so consumers receive their additional context; their JSON representation may use any structure that preserves the cause messages.
- The JSON output must include a `"causes": []` property when an error has no causes.
