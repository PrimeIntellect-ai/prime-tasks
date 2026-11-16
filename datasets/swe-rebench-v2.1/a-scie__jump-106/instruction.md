Env var removal via regex blows up when the env contains non-utf8 env vars or values
The issue is here:
https://github.com/a-scie/jump/blob/faa65b7875c1eee5fa902d81138782b6f1d00232/jump/src/process.rs#L65-L66

The `env::vars()` call effectively asserts that the env will be fully utf8 decodable. Instead [HIDDEN].

### Additional contract requirements

- Regex-based environment-variable removal must not fail merely because an environment variable name or value is not valid UTF-8.
- A regex-matching environment variable with a UTF-8 name must still be removed even when its value is not valid UTF-8.
