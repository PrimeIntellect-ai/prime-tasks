Object config values result in warning about undeclared properties
It looks like the new `flatten` function over-flattens properties that are intended to be arbitrary `Object` values.

**Expected behavior**

A config value that is declared to have an `Object` format should accept an object with arbitrary keys without printing a warning

**Actual behavior**

A warning will be printed for each key inside an object that is assigned to an 'Object' config key.

**Test case**

```js
const convict = require('convict');
const schema = { foo: { format: Object } }; // any 'foo' value that is an object should pass validation

const config = convict(schema);
const foo = { bar: 'baz' }; // this is a valid object
config.set('foo', foo);

config.validate();
// Warning: configuration param 'foo.bar' not declared in the schema
```

I can try my hand at a PR later today unless there's a quick fix that you're aware of.
