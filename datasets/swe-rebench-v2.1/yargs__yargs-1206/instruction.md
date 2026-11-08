Wrong $0 in bundled electron app
We have an election app that is bundled to an .exe file.

A command line like
`bundled.exe -f filename`
will result in:
`
{ _: ['filename'],
  '$0': 'bundled.exe  -f' }
`

The following workaround:
`
const argv = yargs.parse(process.argv.slice(1));
`
will result in
`
{ _: [],
 f: 'filename',
  '$0': 'bundled.exe  -f' }
`

Please notice that the $0 ist still wrong because it contains the "-f".

If this an expected behavior? Is there a way to work around it?

### Additional contract requirements

- When the program is started directly as a bundled executable (its first process argument is the executable itself, not `node`, `iojs` or `electron`), `$0` must be the executable name alone. Options and arguments that follow it on the command line, such as `-f filename`, must not be appended to `$0`.
- When the program is started through `node` or `iojs` with a script, `$0` remains the script path and must not include the arguments that follow the script.
