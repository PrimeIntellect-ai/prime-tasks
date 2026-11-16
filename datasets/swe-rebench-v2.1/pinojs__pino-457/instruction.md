Invalid error JSON logged if stack is undefined
To reproduce:

```js
const logger = require('pino')();
const err = new Error();
delete err.stack;
logger.error(err);

/*
{"level":50,"time":1532087320790,"msg":"","pid":20631,"hostname":"dev.local","type":"Error","stack":undefined,"v":1}
*/
```
Note the section `"stack":undefined` which is not valid JSON.

Real world example: Apollo GraphQL has a custom error class called ApolloError that does not hold `stack` property. When logging an ApolloError we see the issue above which breaks pino's pretty printer among other things.

Pino version: 4.17.3

### Additional contract requirements

- When an error has no `stack` property, its serialized log must omit the `stack` field entirely so the output remains valid JSON.
- Pretty-printing an error without a stack must not fail and must preserve the error message.
