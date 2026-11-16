.commandDir(dir) does not work when the yargs definition script is `require`-ed from other file
While I'm building a tool with `.commandDir(dir)`, an error occured when I require `lib/cli.js` and execute `bin/tool.js`.

`node lib/cli.js` works properly.

Directory tree:
```
.
├── bin
│   └── tool.js
├── lib
│   ├── cli.js
│   └── commands
│       └── foo.js
└── package.json

```

bin/tool.js:
```
#!/usr/bin/env node
require('../lib/cli.js');
```

lib/cli.js:
```
'use strict';
require('yargs')
.commandDir('commands')
.argv;
```

lib/commands/foo.js:
```
'use strict';
exports.command = 'foo';
exports.describe = 'description';
exports.builder = {};
exports.handler = function (argv) { console.log('foo') };

```

The error message is:
```
fs.js:945
  return binding.readdir(pathModule._makeLong(path), options.encoding);
                 ^

Error: ENOENT: no such file or directory, scandir '/Users/popkirby/Documents/yargs-bug/bin/commands'
    at Error (native)
    at Object.fs.readdirSync (fs.js:945:18)
    at requireDirectory (/Users/popkirby/Documents/yargs-bug/node_modules/require-directory/index.js:59:6)
    at Object.self.addDirectory (/Users/popkirby/Documents/yargs-bug/node_modules/yargs/lib/command.js:72:5)
    at Object.Yargs.self.commandDir (/Users/popkirby/Documents/yargs-bug/node_modules/yargs/yargs.js:211:13)
    at Object.<anonymous> (/Users/popkirby/Documents/yargs-bug/lib/cli.js:4:2)
    at Module._compile (module.js:541:32)
    at Object.Module._extensions..js (module.js:550:10)
    at Module.load (module.js:458:32)
    at tryModuleLoad (module.js:417:12)
```
