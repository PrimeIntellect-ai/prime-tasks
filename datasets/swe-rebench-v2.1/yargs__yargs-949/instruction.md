Hidden option is not recognized
An option is not recognised when declared `hidden` by specifying a `falsy` describe.

```js
var yargs = require("yargs");

yargs
.strict()
.option('foo', { type: 'boolean', describe: false })
.parse(['node', 'my-script.js', '--foo']);

// "Unknown argument: foo"
```

```js
var yargs = require("yargs");

yargs
.strict()
.option('foo', { type: 'boolean', describe: 'Foo option' })
.parse(['node', 'my-script.js', '--foo']);

// { foo: true }
```

Am I missing something here?

Thanks!
