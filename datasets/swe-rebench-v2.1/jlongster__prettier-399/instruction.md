Extra parenthesis around function and binary operation
```js
a = function f() {} || b
```

outputs

```js
a = (function f() {
}) || b;
```

but the parenthesis is not needed.

https://jlongster.github.io/prettier/#%7B%22content%22%3A%22a%20%3D%20function%20f()%20%7B%7D%20%7C%7C%20b%5Cn%22%2C%22options%22%3A%7B%22printWidth%22%3A80%2C%22tabWidth%22%3A2%2C%22singleQuote%22%3Afalse%2C%22trailingComma%22%3Afalse%2C%22bracketSpacing%22%3Atrue%2C%22doc%22%3Afalse%7D%7D
