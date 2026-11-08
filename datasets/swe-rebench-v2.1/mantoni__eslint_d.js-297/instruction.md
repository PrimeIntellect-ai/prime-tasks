Can't use eslint_d in multiple projects
I have eslint_d working in 1 project. When trying to use it in another one, I get:

```
$ eslint_d src/app/Content.jsx
node:net:1297
    validatePort(port);
    ^

RangeError [ERR_SOCKET_BAD_PORT]: Port should be >= 0 and < 65536. Received type number (NaN).
    at lookupAndConnect (node:net:1297:5)
    at Socket.connect (node:net:1254:5)
    at Object.connect (node:net:237:17)
    at forwardToDaemon (file:///nix/store/727cpwihd52lvn098wpqhar4r322pgwq-eslint_d-14.0.0/lib/node_modules/eslint_d/lib/forwarder.js:18:22)
    at file:///nix/store/727cpwihd52lvn098wpqhar4r322pgwq-eslint_d-14.0.0/lib/node_modules/eslint_d/bin/eslint_d.js:64:13 {
  code: 'ERR_SOCKET_BAD_PORT'
}

Node.js v20.14.0
```

I'm using eslint_d v14.

### Additional contract requirements

- Add a public function `filesHash(base)` in module `lib/hash.js` that returns a `Promise<string>`.
- `base` is a path to a directory inside a project, for example the project's `node_modules/eslint` directory. The project root is located two directory levels above `base`.
- The function reads the project's `package.json`, `package-lock.json`, `npm-shrinkwrap.json`, `yarn.lock` and `pnpm-lock.yaml` files from the project root and returns a Base64-encoded MD5 hash of the contents it can read, even when another listed file is unavailable.
- If none of these files can be read, the function resolves to the Base64-encoded MD5 hash of an empty string, which is `1B2M2Y8AsgTpgAmY7PhCfg==`.
- The `eslint_d` command must use this project-specific hash, so that running it from a sub-directory of a project uses the same lock files as running it from the project root.
