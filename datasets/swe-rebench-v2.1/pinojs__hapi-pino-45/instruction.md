prettyPrint does not work well with multiple servers
I instantiate 3 different servers and register `hapi-pino` into all 3 with `prettyPrint=true`, but only the first server to register will have pretty logs.

### Additional contract requirements

- With `prettyPrint: true`, log output is rendered as human-readable pretty text rather than as JSON: the logged message appears as plain text and no emitted log line is a JSON object.
- Registering the plugin on multiple servers that share the same `options` object must produce pretty logs for every server, not only the first one registered.
