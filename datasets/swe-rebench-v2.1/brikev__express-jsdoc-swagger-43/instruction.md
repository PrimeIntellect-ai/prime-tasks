[Enhancement] Event emitter feature
We want to expose our package as an event emitter so the user can receive events of what is happening in our parse functions.

This will be very useful for the user as we allow them to know what has been processed or not, the final SwaggerObject, or if there was an error.

We started this development in this [Branch](https://github.com/BRIKEV/express-jsdoc-swagger/tree/event-emitter) but it needs to be updated.

The API of this emitter can be something like this.

```js
const swaggerGenerator = require('express-jsdoc-swagger');
const express = require('express');

const options = {
  info: {
    version: '1.0.0',
    title: 'Albums store',
    license: {
      name: 'MIT',
    },
  },
  file: './simple.js',
  baseDir: __dirname,
};

const app = express();
const generator = swaggerGenerator(app)(options);

// Event emitter API
generator.on('error', error => {
  // user can handle errors
});

generator.on('process', ({ entity, swaggerObject }) => {
  // user can handle swaggerObject status and which entity was evaluated
});

generator.on('finish', swaggerObject => {
  // user can handle see swaggerObject final result
});
```

### Additional contract requirements

- The package's main export is a function `expressJSDocSwagger(app)` that returns a function taking `options`. Calling that function returns an event emitter (an `EventEmitter` instance) that emits:
  - `'process'` with `{ entity, swaggerObject }` for each processing stage, where `entity` is one of `'basicInfo'`, `'securitySchemas'`, `'paths'`, `'components'`, `'tags'`;
  - `'finish'` with the final SwaggerObject once processing completes;
  - `'error'` with the error when processing fails.
- A module `swaggerEvents` exports a function `swaggerEvents()` that returns a singleton API object with:
  - `instance`: the shared `EventEmitter`;
  - `error(errorInfo)`: emits `'error'` on `instance` with `errorInfo`;
  - `processFile(info)`: emits `'process'` on `instance` with `info`;
  - `finish(info)`: emits `'finish'` on `instance` with `info`.
  The same object and the same underlying `EventEmitter` are returned on every call.
- A module `processSwagger` exports `processSwagger(options, logger)` that returns a Promise resolving to the complete SwaggerObject. The optional `logger` callback is invoked once after each processing stage with `{ entity, swaggerObject }`, where `entity` is, in order, `'basicInfo'`, `'securitySchemas'`, `'paths'`, `'components'`, `'tags'`.
