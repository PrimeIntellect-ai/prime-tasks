Diktat codestyle should prohibit empty line before the closing quote
```
fun foo() {
    bar()

}
```

the following code should be prohibited

### Additional contract requirements

- The rule must detect and report an empty line placed immediately before a block's closing delimiter (the closing brace `}`), including when several consecutive empty lines precede it.
- The rule must also automatically fix such a violation by removing the empty line(s) before the closing delimiter, so that the closing delimiter directly follows the last statement of the block. Empty lines that are not adjacent to a closing delimiter (for example, a single separating line between two declarations) must be preserved.
- For the following source, report the blank line after `bar()` at line 3, column 14 and the blank line after the function's closing brace at line 5, column 6. The exact diagnostic message is `do not use more than two consecutive blank lines`:

  ```kotlin
  class Example {
      fun foo() {
          bar()

      }

  }
  ```
