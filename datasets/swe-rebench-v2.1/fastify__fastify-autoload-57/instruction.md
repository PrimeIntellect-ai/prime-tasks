Automatically wrap route files
## 🚀 Feature Proposal

We're migrating an API to fastify and somehow the boilerplate

```
module.exports = function (fastify, opts, next) {
  fastify.route({
    method: 'GET',
    url: '/',
    handler
  })
}
```

feels a bit clunky. I'd like to propose just the route content in a file:

```
module.exports = {
  method: 'GET',
  url: '/',
  handler
}
```

For most cases this is totally sufficient. If additional config/options are required, a regular plugin/route function can be exported.

## Motivation

As mentioned above, the plugin structure feels a bit clunky in each and every file.

## Example

The default type is a function and the new proposal would be an object (method is always required anyway), so I'm thinking somewhere along the lines of (https://github.com/fastify/fastify-autoload/blob/master/index.js#L110):

[HIDDEN]

This is non-breaking, but to be safe it could also be flagged with an new option "wrapRoutes" or something like that.

I'm testing this locally, but I'm currently getting an error when running `npm test`?

```
test/error.js ......................................... 1/2
  not ok should match pattern provided
    found: >-
      Unexpected token '}' at
      /Users/patrick/Sites/fastify-autoload/test/error/lib/a.js:6
    pattern: '/Unexpected token \} at .*\/test\/error\/lib\/a.js:6/'
    at:
      line: 14
      column: 5
      file: test/error.js
    stack: |
      test/error.js:14:5
      Object._encapsulateThreeParam (node_modules/avvio/boot.js:408:13)
      Boot.callWithCbOrNextTick (node_modules/avvio/boot.js:339:5)
      release (node_modules/fastq/queue.js:127:16)
      Object.resume (node_modules/fastq/queue.js:61:7)
      node_modules/avvio/boot.js:155:20
      node_modules/avvio/plugin.js:178:7
      done (node_modules/avvio/plugin.js:136:5)
      check (node_modules/avvio/plugin.js:147:7)
    source: |
      t.match(err.message, /Unexpected token \} at .*\/test\/error\/lib\/a.js:6/)
```

### Additional contract requirements

- Autoloaded files that export route-configuration objects with a `method` must be registered as routes, and their declared route behavior must be reachable.
- Regular function-based route or plugin exports must remain supported, including when additional configuration or options are needed.
