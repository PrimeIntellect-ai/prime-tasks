TypeError on anonymous indexer
[test case](https://flow-to-ts.netlify.com/#%7B%22code%22%3A%22%2F%2F%20%40flow%5Cntype%20Foo%20%3D%20%7B%5Cn%20%20%5Bstring%5D%3A%20number%2C%5Cn%7D%3B%22%2C%22options%22%3A%7B%22prettier%22%3A%7B%22semi%22%3Atrue%2C%22singleQuote%22%3Afalse%2C%22tabWidth%22%3A4%2C%22trailingComma%22%3A%22all%22%2C%22bracketSpacing%22%3Afalse%2C%22arrowParens%22%3A%22avoid%22%2C%22printWidth%22%3A80%7D%2C%22inlineUtilityTypes%22%3Afalse%7D%7D)

### Additional contract requirements

- Converting a Flow object type that contains an anonymous indexer, such as `{ [number]: string }`, must complete without throwing a TypeError.
- The converted TypeScript must declare that member as an index signature whose key type is `number` and whose value type is `string`. When the Flow indexer has no key name, the TypeScript index signature parameter is named `key`, so the output reads `[key: number]: string;`.
