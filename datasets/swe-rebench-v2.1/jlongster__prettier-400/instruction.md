Invalid trailing commas with rest as last argument
```js
[
  ...a
] = [];
```

outputs with trailing comma

```js
[
  ...a,
] = [];
```

which is invalid. We shouldn't output trailing commas when there's a rest argument at the end.

https://jlongster.github.io/prettier/#%7B%22content%22%3A%22%5B%5Cn%20%20...a%5Cn%5D%20%3D%20%5B%5D%3B%5Cn%22%2C%22options%22%3A%7B%22printWidth%22%3A0%2C%22tabWidth%22%3A2%2C%22singleQuote%22%3Afalse%2C%22trailingComma%22%3Atrue%2C%22bracketSpacing%22%3Atrue%2C%22doc%22%3Afalse%7D%7D
