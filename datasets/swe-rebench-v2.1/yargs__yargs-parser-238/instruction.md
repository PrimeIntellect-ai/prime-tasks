unknown-options-as-args doesn't work properly when a property has a number at the end.
unknown-options-as-args doesn't work properly when a property has a number at the end.


```js
require('yargs-parser')(['--str', '--num1'], {
    alias:{ 'num': ['n'] },
    configuration: {
      'unknown-options-as-args': true,
    }
});
```

Actual output
```js
Object {_: ["--str"], num1: true}
```

Expected Output
```js
Object {_: ["--str", "--num1"]}
```

yargs-parser version: 16.1.0
