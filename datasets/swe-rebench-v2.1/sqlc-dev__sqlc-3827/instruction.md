Have process plugins support json as input and output
### What do you want to change?

Example config

```
{
  "version": "2",
  "sql": [
    {
      "schema": "schema.sql",
      "queries": "query.sql",
      "engine": "postgresql",
      "codegen": [
        {
          "out": "gen",
          "plugin": "jsonb"
        }
      ]
    }
  ],
  "plugins": [
    {
      "name": "jsonb",
      "process": {
        "cmd": "test_json_process_plugin",
        "format": "json"
      }
    }
  ]
}
```

### What database engines need to be changed?

_No response_

### What programming language backends need to be changed?

_No response_
