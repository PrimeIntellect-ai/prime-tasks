Call the wrong command handler in some situation
I'm not sure if this is a bug...

I just add two commands:

```javascript
// cli.js
#!/usr/bin/env node
var yargs = require('yargs');
yargs.command('foo', 'the foo command', {}, function(argv) {
  console.log('command foo--', argv);
});
yargs.command('bar', 'the bar command', {}, function(argv){
  console.log('command bar--', argv);
});
console.log(yargs.parse(process.argv.slice(2)));
```

```bash
$ ./cli.js foo
```

It call command foo's handler, and print: `command foo-- { _: [ 'foo' ], '$0': 'cli.js' }`.

```bash
$ ./cli.js bar foo
```

***It also call command foo's handler! But I think it should call command bar's handler.***

And I dig into the source code, <https://github.com/yargs/yargs/blob/master/yargs.js#L645>:

```javascript
if ([HIDDEN] && cmd !== completionCommand) {
  setPlaceholderKeys(argv)
  return command.runCommand(cmd, self, parsed)
}
```

[HIDDEN]
