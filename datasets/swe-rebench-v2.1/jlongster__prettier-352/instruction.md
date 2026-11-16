While doesn't indent expressions
```js
if (a && b && c) {}
while(a && b && c) {}
```

outputs

```js
if (
  a &&
    b &&
    c
) {
}
while (a &&
  b &&
  c) {
}
```

It is weird that `if` puts the condition in a new line but not `while`. `while` is incorrect here.

### Additional contract requirements

- When the condition of a `while` statement does not fit on one line, it must be printed with exactly the same layout as the condition of an `if` statement with the same expression: the same line break after the opening parenthesis, the same indentation of the wrapped condition, and the same indentation of each continued logical operand.
