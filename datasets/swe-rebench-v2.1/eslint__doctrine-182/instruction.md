Support type expression for @this tag
See #143

The current implementation only supports one name in the expression:
```js
/**
 * @this {Widget}
 */
```

UnionType of NameExpression should be supported as well:
```js
/**
 * @this {Widget|Button}
 */
```
