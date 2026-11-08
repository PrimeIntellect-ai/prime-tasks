yargs-parser crashes when passed a `--toString` option
Follow-up of the bugs fixed by #227.

With a code as simple as:
```jsconst Parser = require('yargs-parser')
Parser(process.argv.slice(2))
```

yargs-parser crashes on a `--toString` option:
```bash
$ node index.js --toString
...\yargs\yargs-parser\index.js:426
      flags.aliases[key].forEach(function (x) {
                         ^

TypeError: flags.aliases[key].forEach is not a function
    at setArg (C:\Users\pwhl824\Dev\yargs\yargs-parser\index.js:426:26)
    at parse (C:\Users\pwhl824\Dev\yargs\yargs-parser\index.js:202:11)
    at Parser (C:\Users\pwhl824\Dev\yargs\yargs-parser\index.js:960:16)
    at Object.<anonymous> (C:\Users\pwhl824\Dev\yargs\yargs-parser-tests\index.js:2:1)
    at Module._compile (internal/modules/cjs/loader.js:701:30)
    at Object.Module._extensions..js (internal/modules/cjs/loader.js:712:10)
    at Module.load (internal/modules/cjs/loader.js:600:32)
    at tryModuleLoad (internal/modules/cjs/loader.js:539:12)
    at Function.Module._load (internal/modules/cjs/loader.js:531:3)
    at Function.Module.runMain (internal/modules/cjs/loader.js:754:12)
```
