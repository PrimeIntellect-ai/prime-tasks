Allow omission of type in returns tag
Currently doctrine permits syntax like

```js
/**
 * @param foo - this is a param
 */
```

But not the same for return values

```js
/**
 * @returns foo - this is a return value
 */
```

Having both tags with optional type annotations would be great since the type annotations can often inferred by Flow/TS.
