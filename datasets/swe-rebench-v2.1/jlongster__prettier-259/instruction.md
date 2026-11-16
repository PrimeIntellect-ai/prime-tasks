Missing parenthesis for functions left of a template literal
```js
(function() {})()``;
(function() {})``;
```

outputs

```js
function() {}()``;
function() {}``;
```

which is invalid

https://jlongster.github.io/prettier/#%7B%22content%22%3A%22(function()%20%7B%7D)()%60%60%3B%5Cn(function()%20%7B%7D)%60%60%3B%5Cn%22%2C%22options%22%3A%7B%22printWidth%22%3A80%2C%22tabWidth%22%3A2%2C%22singleQuote%22%3Afalse%2C%22trailingComma%22%3Afalse%2C%22bracketSpacing%22%3Atrue%7D%7D

Those test262 are testing crazy things :p
