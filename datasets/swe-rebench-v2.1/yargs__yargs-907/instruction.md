Using .conflicts and .option
I'm porting a big project over from using `commander` and I am absolutely loving yargs but encountered this issue.

with yargs 8.0.2:
```

const yargs = require("yargs");
yargs('command --foo')
          .command('command', 'a command', {}, function (argv) {})
	  .option('foo', {describe:'A foo foo'})
          .option('bar',{describe: 'A bar bar'})
          .fail(function (msg) {
            console.log(msg);

          })
          .conflicts('foo', 'bar')
.argv
```

Results in "Arguments foo and bar are mutually exclusive" despite the fact that "bar" is not specified on the command.   From the doc: "This method can be used to make yargs aware of options that could exist." (i.e. it does not imply that you are setting those options to be true).  If I comment out `.option('bar'...` it works as expected.

I was trying to debug this condition in lib\validation.js but  couldn't find a way to make it work
```
 [HIDDEN]
```

 Any insight?

### Additional contract requirements

- Declaring an option in a conflict pair does not count as supplying it. Validation must not report a conflict when only one of the conflicting options is supplied.
