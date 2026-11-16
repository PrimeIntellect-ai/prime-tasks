Feature Request: Option to ignore ENOENT in [HIDDEN]
The `npm start` for one of my web apps runs a fastify server which uses fastify-static twice:
```js
fastify
  .register(fastifyStatic, {
    prefix: '/dev/',
    root: path.resolve('src')
  })
  .register(fastifyStatic, {
    prefix: '/app/',
    root: path.resolve('dist')
  })
```
The `src` directory always exists, this is the unmodified source.  `dist` may or may not exist, it is the product of `gulp build`.  Right now I use `fs.mkdirSync(path.resolve('dist'), {recursive: true})` before initializing the fastifyStatic plugin to suppress the `"root" path "${rootPath}" must exist` error.  It would be nice if I did not have to force creation of the empty folder for this to work, just let normal 404 logic deal with ENOENT at request time.

Are you open to this?

### Additional contract requirements

- When the configured root path does not exist, log a warning with the exact message `"root" path "${rootPath}" must exist`, substituting the configured path for `${rootPath}`.
- A configured root path that does not exist must not prevent the server from starting.
- Requests for missing files under a configured root that does not exist must be handled as normal 404s.
