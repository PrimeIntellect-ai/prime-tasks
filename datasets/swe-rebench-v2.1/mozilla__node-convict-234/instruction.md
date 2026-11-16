Object config values result in warning about undeclared properties
Hello,

I would like to suggest a small improvement over #213 from @mmcgahan.

We use multiple custom formats that are in the end nothing more than objects that we would like to validate in a specific way. We are receiving warnings when loading the base schema and not even loading configurations on top of it. Here's an example:

```javascript
const convict = require('convict');

const schema = {
  foo: {
    format: 'bar',
    default: {
      baz: 'blah',
    },
  },
};

convict.addFormats({ bar: { validate() {} } });
const config = convict(schema);
config.validate();
// Warning: configuration param 'foo.baz' not declared in the schema
```

Since `foo` is after all an object, we believe that the warning behavior there should be the same than for the format `Object`. Is there a known fix for that issue?

Otherwise, please have a look at #234.
