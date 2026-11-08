requiresArg is enforced when option is not passed
index.js
```
const yargs = require('yargs');

yargs.options({
  a: {
    type: "string",
    requiresArg: true
  },
});
console.log(yargs.argv);
```
`node index.js` now fails, but it worked in versions prior 10.0.3.

I ran into the problem when using webpack-dev-server, but I think it probably is not the only thing being affected.

I have spent some time on this, and found the behavior was introduced in https://github.com/yargs/yargs/pull/1015.
