The `type` of the hash(#) token is not a string.
I'm using babel-eslint@8.2.6.

Parsing the following source code with `babel-eslint` creates an invalid token.

```js
  export default class TouristNumber extends Vue {
    #pro1='hello'
  }
```

token:

```ts
Token {
  type:
   TokenType {
     label: '#',
     keyword: undefined,
     beforeExpr: false,
     startsExpr: false,
     rightAssociative: false,
     isLoop: false,
     isAssign: false,
     prefix: false,
     postfix: false,
     binop: null,
     updateContext: null },
  value: undefined,
  start: 92,
  end: 93,
  loc: SourceLocation { start: { line: 4, column: 0 }, end: { line: 4, column: 1 } },
  range: [ 92, 93 ] }
```

The `type` of the token must be a string.
https://eslint.org/docs/developer-guide/working-with-custom-parsers#the-ast-specification

But the result is not a string.

[HIDDEN]

---

ref https://github.com/vuejs/eslint-plugin-vue/issues/814

### Additional contract requirements

- For the hash token, `type` must be "Punctuator" and `value` must be "#".
