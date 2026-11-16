Carriage return replacement breaking LaTeX
## Expected Behavior

In a text document use of an escaped backslash before an `r` character should not remove the `r` character. This is necessary for e.g., LaTeX, where commands like `\right`) are common.

See https://github.com/remarkablemark/html-react-parser/issues/1634

## Actual Behavior

All `\r` are removed from the HTML string, even if the raw string is formatted as `\\r`.

Caused by #902

## Steps to Reproduce

```js
parse('<span class="math">\\left(\\right)\\rD\\rightarrow\\reals\\ni</span>');
```

## Reproducible Demo

https://stackblitz.com/edit/html-react-parser-typescript-w9j4u9vu?file=src%2Findex.tsx

## Environment

- Version: [5.0.11](https://github.com/remarkablemark/html-dom-parser/releases/tag/v5.0.11)
- Platform:
- Browser:
- OS:

## Keywords

LaTeX, carriage return, escape, unescape, special character
