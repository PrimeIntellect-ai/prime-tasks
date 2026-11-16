options without description to not appear in --help
`yargs@7.0.2`

```js
#!/usr/bin/env node

// @flow

import yargs from 'yargs';
import passthroughService from './commands/passthroughService';

yargs
  .command(passthroughService)
  .option('logstash', {
    describe: 'Logstash host:port'
  })
  .help()
  .parse(process.argv.slice(1));

```

```js
// ./commands/passthroughService;

export default {
  builder: (yargs: Object) => {
    return yargs
      .options({
        forward: {
          type: 'string'
        },
        listen: {
          default: 'http://0.0.0.0:3000',
          type: 'string'
        }
      });
// [..]
```

```bash
$ babel-node src/bin/forwardProxy.js passthrough-service --help
Options:
  --logstash  Logstash host:port
  --help      Show help                                                [boolean]
  --listen                             [string] [default: "http://0.0.0.0:3000"]
```

Note the missing `forward` option.

### Additional contract requirements

The reported issue is that options registered without a description were being omitted
from the generated `--help` output. The required behaviour is:

- An option registered without a `describe`/`description` value is still listed in the
  generated `--help` output (its description column is simply empty), unless it is
  marked `hidden: true`.
- An option marked `hidden: true` is omitted from the generated `--help` output but is
  still accepted and parsed on the command line.
