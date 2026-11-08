Unknown arguments cause incorrect command positional `coerce()`
As evidenced in https://github.com/lerna/lerna/issues/2315, when arguments are passed after `--` with the default `parserConfiguration` (append them to `argv._`), `yargs@14.2.0` causes an incorrect `coerce("")` call on a command's positional argument, as well as re-parsing any flags (which fails when `strict()` is enabled).

```js
require('yargs')
  .strict()
  .option('loglevel', {
    type: 'string',
  })
  .command('repro [stuff]', 'example', yargs => {
    yargs.positional('stuff', {
      describe: 'things',
      coerce: stuff => {
        if (stuff === '') {
          throw new Error('fail');
        }
        return stuff;
      },
    });
  }, argv => {
    console.log(argv);
  })
  .parse('repro -- --loglevel=woo');
```

It _also_ causes the valid `--loglevel` option in the example above to fail, once the `coerce()` method is modfied to ensure that the parameter is in fact non-empty first (or if it's an identity function `stuff => stuff`, or removed entirely). So that's fun.

The current workaround is to enable `populate--` in yargs-parser:
```js
  .parserConfiguration({
    "populate--": true,
  })
```

This seems sub-optimal.

### Additional contract requirements

- `parserConfiguration(config)` is a chainable method on a Yargs instance: it accepts a plain object and returns the same instance.
- The boolean configuration key `'populate--'` controls how arguments after `--` are exposed on the parsed argv. When `'populate--'` is `true`, those arguments are available as `argv['--']`; when it is `false` (the default), they are appended to `argv._`.
