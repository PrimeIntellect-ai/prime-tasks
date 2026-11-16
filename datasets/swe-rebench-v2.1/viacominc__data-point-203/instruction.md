Change order of execution for entity type checking
**Problem description**:

The `inputType` and `outputType` entity methods are not the first/last to be executed, because middleware can be executed before and after those type checks occur. Here's an example of where that becomes a problem:

```js
const dataPoint = DataPoint.create({
  entities: {
    'model:thing': {
      value: () => 'THIS IS A STRING',
      after: input => input.toLowerCase(),
      outputType: 'string'
    }
  }
})

dataPoint.use('model:after', (acc, next) => {
  acc.resolve(52)
  next(null)
})

// this returns a number despite the outputType: 'string' type check
// resolves in this order: value -> after -> outputType -> 'model:after'
dataPoint.resolve('model:thing', {}) // => 52
```

**Suggested solution**:

`inputType` should be first entity method that's executed; `outputType` should be the last. There should not be any middleware executed before `inputType` or after `outputType`.
