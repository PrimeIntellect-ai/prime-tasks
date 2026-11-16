Missing parenthesis for typeof and arrow functions
```js
typeof (() => {});
```

outputs

```
typeof () => {};
```

which is invalid

https://jlongster.github.io/prettier/#%7B%22content%22%3A%22typeof%20(()%20%3D%3E%20%7B%7D)%22%2C%22options%22%3A%7B%22printWidth%22%3A80%2C%22tabWidth%22%3A2%2C%22singleQuote%22%3Afalse%2C%22trailingComma%22%3Afalse%2C%22bracketSpacing%22%3Atrue%7D%7D
