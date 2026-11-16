Environment variables through phpbench.json
```json
{
    "bootstrap": "vendor/autoload.php",
    "path": "src/Benchmark",
    "env": [
        {
            "name": "APP_ENV",
            "value": "test",
            "force": true
        },
        {
            "name": "SOME_VAR",
            "value": "foo bar"
        }
    ]
}
```

Are there any plans to implement something like this? This would help a lot when writing benchmarks when working with a database in a test environment...

What do you think about this?

### Additional contract requirements

- `phpbench.json` accepts an option named `runner.php_env` whose value is an object mapping environment variable names to string values.
- Every variable in `runner.php_env` is visible through the environment of the PHP process that executes a benchmark, so a benchmark can read it with `getenv()`.
