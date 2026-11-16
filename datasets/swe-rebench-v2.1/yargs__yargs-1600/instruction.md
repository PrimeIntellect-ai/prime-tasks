The updateStrings() could not work on 'Options:'
```
   .updateStrings({
        command: chalk.cyan('command'),
        'Examples:': cyanUnderline('Examples:'),
        'Commands:': cyanUnderline('Commands:'),
        'Options:': cyanUnderline('Options:'),
        'Invalid values:': `${chalk.bgBlack.red('ERR! ')}${chalk.bold('Invalid values:')}`,
      })
```
the `Options:` location update can't work correctly.  cause of
[HIDDEN]
while we show help like `cmd -h` [HIDDEN]

it's bug?     `BTW  yargs v15.1.0  works fine.`

### Additional contract requirements

- When help is displayed, the default `Options:` group heading must use the replacement configured for `'Options:'` through `updateLocale()` or its `updateStrings()` alias, including when help is requested with `-h`.
