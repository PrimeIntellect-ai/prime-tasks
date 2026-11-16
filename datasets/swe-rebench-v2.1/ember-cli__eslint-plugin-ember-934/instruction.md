order-in-models: TypeError: Cannot read property 'name' of undefined
Occurred while linting

```js
return Model.create({
  ...data,
  foo,
  bar,
});
```

at

https://github.com/ember-cli/eslint-plugin-ember/blob/be053df9c31305c67d30d961c65aefc8077574a7/lib/utils/property-order.js#L63

Looks similar to https://github.com/ember-cli/eslint-plugin-ember/issues/284.

eslint-plugin-ember version: 8.13.0
ESLint version: 7.7.0
Parser: babel-eslint 10.1.0
Node.js version: 12.18.3

### Additional contract requirements

- The `order-in-components`, `order-in-controllers`, `order-in-models`, and `order-in-routes` rules accept `'spread'` as a property type in their `order` configuration, and treat spread syntax as ordered before every other property type.
- The exported `determinePropertyType(node, parentType, ORDER)` function in `lib/utils/property-order.js` returns `'spread'` when `node` is an `ExperimentalSpreadProperty`.
- Autofixing `export default Component.extend({
  role: "sloth",
  ...spread,
});` produces exactly:
  ```js
  export default Component.extend({
    ...spread,
    role: "sloth",
  });
  ```
