Confusing behavior around duration config loaded from external file
### Steps to reproduce
1. Create an _index.js_ file and paste the following code:
    ```js
var convict = require('convict');

var conf = convict({
      session: {
        doc: 'a doc',
        format: 'duration',
        default: '2 days'
      }
});

conf.loadFile('./config.json');
conf.validate();

console.log(conf.get('session'));
```

2. Create a _config.json_ file in the same directory as _index.js_ created in step 1:
    ```json
{
      "session": "4 days"
}
```

3. Run `node index`

### Actual results:
```sh
$ node index

/Users/pdehaan/dev/tmp/convict-test/node_modules/convict/lib/convict.js:393
        throw new Error(errBuf);
              ^
Error: session: must be a positive integer: value was "2 days"
    at Object.rv.validate (/Users/pdehaan/dev/tmp/convict-test/node_modules/convict/lib/convict.js:393:15)
    at Object.<anonymous> (/Users/pdehaan/dev/tmp/convict-test/index.js:12:6)
    at Module._compile (module.js:456:26)
    at Object.Module._extensions..js (module.js:474:10)
    at Module.load (module.js:356:32)
    at Function.Module._load (module.js:312:12)
    at Function.Module.runMain (module.js:497:10)
    at startup (node.js:119:16)
    at node.js:906:3
```

This seems to be because of the "2 days" in the _config.json_ file. It works fine when I set the "default" value in the _index.js_ but implodes horribly in the JSON file.

### Workaround:
Set the duration as milliseconds in the `config.json` file.
