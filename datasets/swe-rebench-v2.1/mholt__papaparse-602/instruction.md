QuoteChar option in `unparse` blows up the parser if it's a regex special char
If you specify a regex special char as a quoteChar then the library blows up:

```
Papa.unparse('[{"a": "1", "b": "2", "c": "3"}]', { quoteChar: '(' })
```

> papaparse.min.js:6 Uncaught SyntaxError: Invalid regular expression: /(/: Unterminated group
>    at new RegExp (<anonymous>)
>    at Object.b [as unparse] (papaparse.min.js:6)
>    at <anonymous>:1:6

### Additional contract requirements

- When `Papa.unparse([['a,d','b','c']], { quoteChar: '(' })` is called, it must return exactly `(a,d(,b,c`.
