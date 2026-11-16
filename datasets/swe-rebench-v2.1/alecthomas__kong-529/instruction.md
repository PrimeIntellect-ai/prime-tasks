Support parsing integer literals
When typing a long integer number, using underscore characters between successive digits can improve readability. For instance, for the number `1000000000`, it becomes `1_000_000_000` with underscore characters. This is easy to read. This is also the format defined in the Go spec https://go.dev/ref/spec#Integer_literals

> For readability, an underscore character _ may appear after a base prefix or between successive digits; such underscores do not change the literal's value.

Kong cannot parse an int string like `1_000`. It would return an error

```
expected a valid 64 bit int but got "10_000_000"
```
