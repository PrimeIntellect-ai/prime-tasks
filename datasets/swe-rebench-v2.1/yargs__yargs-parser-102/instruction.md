Inconsistent parsing of arrays with dot-notation when argument order is switched
The way an array argument is parsed changes depending on whether I parse `--config.compression=store --config ./electron.config.json` vs. `--config ./electron.config.json --config.compression=store`

When I run:
```
var argv = require("yargs-parser")('--config.compression=store --config ./electron.config.json')
```

The value of `argv.compression` is
```json
[
  {
    "compression": "store"
  },
  "./electron.config.json"
]
```

But when I swap the arguments and run:
```
var argv = require("yargs-parser")('--config ./electron.config.json --config.compression=store')
```

The value of `argv.compression` is
```json
"\"./electron.config.json\""
```

I would expect them both to equal the result of the first command. Is there a reason for this, or is it a bug?

### Additional contract requirements

The reporter's expectation that the two orders "equal the result of the first
command" means that both orders must parse the dot-notation option as an array
of the same shape, rather than one order producing an array and the other a
scalar string. The elements of that array appear in the order in which the
corresponding arguments appear on the command line. So:

- `--foo.bar baz --foo bux` gives `foo` equal to `[ { bar: 'baz' }, 'bux' ]`.
- `--foo bux --foo.bar baz` gives `foo` equal to `[ 'bux', { bar: 'baz' } ]`.

The same applies when the dot-notation argument uses `=` (for example
`--foo.bar=baz`). When several dot-notation arguments are combined with a plain
argument, each contributes one element, in command-line order.
