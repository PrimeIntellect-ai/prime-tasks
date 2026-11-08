v7 doesn't work as described
The breaking change in v7 turned the example from the `README.md` useless:

```
const {serializeError, deserializeError} = require('serialize-error');

const error = new Error('🦄');

console.log(error);
//=> [Error: 🦄]

const serialized = serializeError(error)

console.log(serialized);
//=> {name: 'Error', message: '🦄', stack: 'Error: 🦄\n    at Object.<anonymous> …'}

const deserialized = deserializeError(serialized);
//=> [Error: 🦄]
```

The serialized error looks just like an empty object now, and is missing the `name`, `message`, and `stack` properties on the console. Actually, for me this was the most useful feature, and hence v7 is a huge step into the wrong direction.

I understand that you wanted to change it this way to keep things consistent – however, is there a chance to make this configurable?

### Additional contract requirements

The serialized result's `name`, `message`, and `stack` properties are enumerable by default. Callers can configure whether each property is enumerable by changing its `enumerable` descriptor on the returned object with `Object.defineProperty`; each property must therefore be configurable.
