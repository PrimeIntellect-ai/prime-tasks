v0.6.11 broke some specific schemas
I use UUID literals nested keys in validation schema its work on 0.6.10 and was broken in 0.6.11.
Simple example code:
```js
const schema = {
  minPrice: {
    type: 'object',
    props: {
      value: { type: 'number', positive: true, integer: true },
      enabled: 'boolean',
      regions: {
        type: 'object',
        optional: true,
        props: { '12345678-ef85-4c62-b8f3-e00fbbc155d4': { type: 'number', positive: true, integer: true, optional: true } },
      },
    },
  },
};

/**
 * Next line throws
 * SyntaxError: Invalid or unexpected token
 * at new Function (<anonymous>)
 * at Validator.compileSchemaObject (node_modules\fastest-validator\lib\validator.js:114:33)
 * at Validator.compileSchemaRule (node_modules\fastest-validator\lib\validator.js:154:24)
 * at Validator.compileSchemaType (ec-order\node_modules\fastest-validator\dist\index.js:472:15)
 *
 * Generated code looks like
 * propertyPath = (path !== undefined ? path + ".12345678-ef85-4c62-b8f3-e00fbbc155d4" : "12345678-ef85-4c62-b8f3-e00fbbc155d4");
 [HIDDEN]
 * if (res !== true) {             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
 *  this.handleResult(errors, propertyPath, res);
 * }
 */
const result = v.validate(data, schema);
```

At the moment, I don't have enough time to make a pull request.

### Additional contract requirements

- Validation must compile schemas with nested object properties keyed by UUID literals and validate those values according to the property's declared rules, without throwing a syntax error during compilation.
