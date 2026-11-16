A coerce function runs again for each alias
The coerce function for an argument with an alias will run multiple times, the initial run and then once more per alias.

I only noticed as I was using the file coercion example and reading a largish file.

```
let argv = require('yargs')
  .alias('file', 'f2')
  .alias('file', 'f3')
  .coerce('file', function (arg) {
    console.log('reading file', arg)
    return require('fs').readFileSync(arg, 'utf8')
  })
  .argv
```
then
```
$ node testyargs.js  --file test
reading file test
reading file test
reading file test
```

from https://github.com/yargs/yargs/issues/729
