Language server provides completions within constant strings
If you type the following code:
```gleam
const x = "io.|"
```
The language server provides completions such as `io.println`. This should not happen inside strings.
