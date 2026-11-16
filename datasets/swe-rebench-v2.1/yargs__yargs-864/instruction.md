strict seems to overlook parameters in command strings
I'm not sure whether it's my mistake or a misunderstanding but I get errors for sub-command parameters when I enable `strict()` in global mode.

Here's my code:
```js
// index.js
const yargs = require('yargs');

yargs
  .commandDir('./commands')
  .demandCommand(1)
  .strict(true)
  .help()
  .alias('help', 'h')
  .argv;
```

```js
// commands/export.js
exports.command = 'export';
exports.describe = 'export';
exports.builder = yargs => {
  return yargs
    .command('all', 'desc0')
    .command('handed-in [id]', 'desc1')
    .command('by-prop <property> <value>', 'desc2')
    .command('by-reg-nr <regNr>', 'desc3')
    .demandCommand();
};
exports.handler = () => {}
```

When I invoke this script for commands with properties, I keep getting errors:
```bash
$ ./index.js export by-prop 1 2
/usr/bin/nodejs index.js export by-prop <property> <value>

Options:
  --help, -h  show help                                           [boolean]

Unknown arguments: property, value
$ ./index.js export handed-in 1
/usr/bin/nodejs index.js export handed-in [id]

Options:
  --help, -h  show help                                           [boolean]

Unknown argument: id
```
Setting the strict mode in `index.js` to non-global and enabling the strict mode in `command.js` fixes the problem, but why?

### Additional contract requirements

When strict mode is enabled globally, positional arguments declared in nested command strings are recognized as positional arguments rather than reported as unknown arguments. This applies to both required and optional positional arguments, including nested commands without handlers.
