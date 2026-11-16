[bug] sg run -c worng.yml should report error
### Please read the FAQ for the bug you encountered.

- [x] I have read the existing FAQ

### ⏯ Playground Link

N/A

### 💻 Code

```bash
sg run -c invalid.yml -p test
```

This command should report the yaml

### 🙁 Actual behavior

not reporting error. ast-grep just silently ignored the wrong configuration.

### 🙂 Expected behavior

reporting error

### Additional information about the issue

_No response_

### Additional contract requirements

- When the specified configuration file cannot be parsed, the command must fail and include `Cannot parse configuration` in stderr. When the specified configuration file cannot be read because it does not exist, the command must fail and include `Cannot read configuration` in stderr.
