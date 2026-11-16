Comment between if/else is formatted strangely
```js
if(x) {
}
// comment
else {
}
```

output:

```js
if (x) {
} else
  // comment
  {
  }
```

### Additional contract requirements

- Also, format `if (1)\n// comment\n{\n  false\n}` as `if (1) {\n  // comment\n  false;\n}`. For `if (1) {\n} else\n  // Comment\n  {\n  }`, format it as `if (1) {\n} else {\n  // Comment\n}`.
