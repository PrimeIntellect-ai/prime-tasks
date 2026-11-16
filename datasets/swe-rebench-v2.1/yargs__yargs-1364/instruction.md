.strict() allows extra args
Documentation states that in strict mode, extra arguments are reported as errors. However, none of the constructs allowed by yargs seems to demonstrate that behaviour. For example, the following configs:

```js
require("yargs")
  .command("foo <bar>")
  .strict()
  .argv
```
```js
require("yargs")
  .command("foo <bar>", "foo cmd", yargs => yargs.strict())
  .strict()
  .argv
```
```js
require("yargs")
  .command({
    command: "foo <bar>",
    builder: yargs => yargs.strict()
  })
  .command({
    command: "baz <qux>",
    builder: yargs => yargs.strict()
  })
  .demandCommand()
  .strict()
  .argv;
```
all result in commands like

```
$ ./cmd foo 123 extra
$ ./cmd bar 456 extra-1 extra-2
```

being accepted without any error.

### Additional contract requirements

- In strict mode, an extra positional argument supplied after a command's declared
  positional arguments must be reported as an error: the parser must invoke the
  configured `.fail()` handler with an error message instead of silently accepting
  the extra argument.
- This must hold for each of the configurations demonstrated above:
  1. a string-form command with `.strict()` on the root parser;
  2. a string-form command whose builder enables strict mode
     (`yargs => yargs.strict()`);
  3. object-form commands whose builders enable strict mode, combined with
     `.demandCommand()`.
- The exact error message text is not part of the contract; any error reported for
  the extra positional argument satisfies the requirement.
