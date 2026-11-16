errors when upgrading to node 10
with https://github.com/tschaub/mock-fs/issues/257 fixed, i attempted again to upgrade [a project of mine](https://github.com/travi/javascript-scaffolder/tree/node-10) to node 10, but was presented with new errors that appear to be related to the mocked filesystem. i've been using the package in a cli that runs in node 10 for a while now and have not run into these errors outside of this testing scenario.

the primary error that i'm seeing now is:

```
Error: EEXIST, file already exists '...path-to-project/javascript-scaffolder/test/unit'
           at Object.<anonymous> (...path-to-project/javascript-scaffolder/node_modules/mock-fs/lib/binding.js:939:13)
           at maybeCallback (...path-to-project/javascript-scaffolder/node_modules/mock-fs/lib/binding.js:68:18)
           at Object.Binding.mkdir (...path-to-project/javascript-scaffolder/node_modules/mock-fs/lib/binding.js:936:3)
           at Object.<anonymous> (...path-to-project/javascript-scaffolder/node_modules/mock-fs/lib/index.js:33:39)
           at mkdir (fs.js:735:11)
           at Promise (internal/util.js:274:30)
           at new Promise (<anonymous>)
           at mkdir (internal/util.js:273:12)
           at makeDir (...path-to-project/javascript-scaffolder/node_modules/make-dir/index.js:52:9)
           at exports.default (...path-to-project/javascript-scaffolder/src/linting/eslint.js:13:50)
           at process._tickCallback (internal/process/next_tick.js:68:7)
```

when attempting to [create a directory](https://github.com/travi/javascript-scaffolder/blob/9bcbef6eb7be7525999ede2acc5eea1aaad0f0d4/src/linting/eslint.js#L13). i have not seen such an error at runtime against a real file system, even when scaffolding over an existing project where that directory is sure to exist.

i'm also seeing the following error at the end of my test suite, but without a stack trace. i'm not sure if it is a result of the other errors happening earlier in the test run or not.

to reproduce, clone [my project](https://github.com/travi/javascript-scaffolder) and run `npm run test:integration` to see that everything passes in the `master` branch. then switch to the `node-10` branch and run the same script to see the errors.

are there still outstanding, known changes necessary for mock-fs to handle actions like this in node 10?

### Additional contract requirements

- When recursive directory creation targets a directory that already exists, both callback-based `fs.mkdir(path, { recursive: true }, callback)` and `fs.mkdirSync(path, { recursive: true })` must succeed without an `EEXIST` error.
