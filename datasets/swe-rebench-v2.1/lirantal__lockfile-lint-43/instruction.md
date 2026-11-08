Packages in local filesystem always yield errors when using -s (yarn)
Thanks for releasing this very important tool! There's one small issue preventing us from adopting it:

## Expected Behavior

If you add a package from the local filesystem (e.g. `yarn add path/to/my/package`), an entry is created in `yarn.lock` corresponding to the package which has no `resolved` field. I would expect this package to be ignored by `lockfile-lint` (or at least to have a flag to ignore it), given that the code is already on the host machine, even when the user has specifically requested to validate protocol schemas (or whitelisted allowed schemes some other way).

## Current Behavior

```console
ABORTING lockfile lint process due to error exceptions

Encountered error Invalid URL: undefined in package: "my-local-package@../my-local-package"

TypeError [ERR_INVALID_URL]: Invalid URL: undefined
    at onParseError (internal/url.js:241:17)
    at new URL (internal/url.js:319:5)
    at ValidateHost.validate (/home/richard/.npm/_npx/31760/lib/node_modules/lockfile-lint/node_modules/lockfile-lint-api/src/validators/ValidateHost.js:30:30)
    at ValidateHostManager (/home/richard/.npm/_npx/31760/lib/node_modules/lockfile-lint/src/validators/index.js:43:20)
    at validators.forEach.validator (/home/richard/.npm/_npx/31760/lib/node_modules/lockfile-lint/src/main.js:35:28)
    at Array.forEach (<anonymous>)
    at Object.runValidators (/home/richard/.npm/_npx/31760/lib/node_modules/lockfile-lint/src/main.js:25:14)
    at Object.<anonymous> (/home/richard/.npm/_npx/31760/lib/node_modules/lockfile-lint/bin/lockfile-lint.js:31:17)
    at Module._compile (internal/modules/cjs/loader.js:778:30)
    at Object.Module._extensions..js (internal/modules/cjs/loader.js:789:10)

error: command failed with exit code 1
```

## Possible Solution

[HIDDEN]

## Steps to Reproduce (for bugs)

https://github.com/richsilv/lockfile-lint-bug-example/tree/master

## Context

We have a single, common shared library required by a variety of different services, and we find it simpler to copy this package into the local filesystem and install from there when building containers than via a private or self-hosted registry. I can't imagine we're the only people doing this (although I'd be interested to know if I was wrong!). For all other, registry-sourced packages, we would certainly want to validate the protocol.

## Your Environment

- Library Version used: 3.0.5
- Node.js version (e.g. Node.js 5.4): 10.16.2
- Operating System and version (desktop or mobile): Ubuntu 18.04

### Additional contract requirements

- Package entries without a `resolved` field must be skipped by host, HTTPS, and allowed-scheme/protocol validation. Entries with a `resolved` field remain subject to the selected validation rules.
