Prevent negative numbers in diagnostics ranges
While working on integrating clojure-lsp with Calva I've noticed this error sometimes:

```text
Notification handler 'textDocument/publishDiagnostics' failed with message: Illegal argument: line must be non-negative
```

When I examined those message types in the trace logs, I see that sometimes a message like this is sent from the server:

```json
{
  "uri": "file:///home/brandon/development/clojure-test/.calva/output-window/output.calva-repl",
  "diagnostics": [
    {
      "range": {
        "start": {
          "line": -1,
          "character": -1
        },
        "end": {
          "line": -1,
          "character": -1
        }
      },
      "severity": 1,
      "code": "syntax",
      "source": "clj-kondo",
      "message": "Can't parse <stdin>, No matching clause: :unknown"
    }
  ]
}
```

After tracing through the code, I'm guessing clj-kondo is providing a row/col of 0/0 when trying to lint Calva's `output.calva-repl` file, which Calva labels as Clojure so that it gets Clojure syntax highlighting, Calva features, etc. Due to its not normal formatting it probably causes parsing errors in clj-kondo. These 0/0 numbers are then decremented to -1/-1 here:

https://github.com/snoe/clojure-lsp/blob/8b984cb261e05d96471f5d6056a1c7ad05675bb5/src/clojure_lsp/shared.clj#L16

I know Calva's usage with this file is not conventional, but since the lsp spec says ranges should contain negative numbers, do you think clojure-lsp should prevent negative numbers in the above function, by either leaving them at 0 if they are 0, or setting them to 0 if they're negative after decrementing?
