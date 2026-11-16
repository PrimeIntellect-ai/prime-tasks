Exception thrown when redacting objects paths that contain a hyphen
Using `pino@5.0.1` and `fast-redact@1.1.13`.

This seems to be an issue specifically w/ the `pino` validation check, as the below test script shows that redaction via `fast-redact` works while the same arguments in `pino` will throw an exception:

```
// test fast-redact and hyphenated object path
const fastRedact = require('fast-redact')
const fauxRequest = {
  headers: {
    'x-access-token': 'super-secret',
    host: 'http://example.com',
    cookie: `oh oh we don't want this exposed in logs in etc.`,
    referer: `if we're cool maybe we'll even redact this`
  }
}
const redact = fastRedact({
  paths: ['headers.cookie', 'headers.referer', 'headers["x-access-token"]']
})

console.log('\n');
console.log(redact(fauxRequest))
console.log('\n');

// test pino instantiation w/ the same arguments for redaction
const logger = require('pino')({ redact: { paths: ['headers.cookie', 'headers.referer', 'headers["x-access-token"]' ] } });
```

-->

```

{"headers":{"x-access-token":"[REDACTED]","host":"http://example.com","cookie":"[REDACTED]","referer":"[REDACTED]"}}


/home/austin/code/common/node_modules/fast-redact/lib/validator.js:38
        throw Error(ERR_INVALID_PATH(s))
        ^

Error: fast-redact – Invalid path ("x-access-token"])
    at paths.forEach (/home/austin/code/common/node_modules/fast-redact/lib/validator.js:38:15)
    at Array.forEach (<anonymous>)
    at validate (/home/austin/code/common/node_modules/fast-redact/lib/validator.js:18:11)
    at fastRedact (/home/austin/code/common/node_modules/fast-redact/index.js:36:3)
    at Object.keys.reduce (/home/austin/code/common/node_modules/pino/lib/redaction.js:44:17)
    at Array.reduce (<anonymous>)
    at redaction (/home/austin/code/common/node_modules/pino/lib/redaction.js:41:29)
    at pino (/home/austin/code/common/node_modules/pino/pino.js:65:33)
    at Object.<anonymous> (/home/austin/code/common/scratch.js:18:31)
    at Module._compile (module.js:652:30)

```
