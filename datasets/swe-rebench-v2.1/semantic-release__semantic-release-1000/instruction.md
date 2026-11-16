Plugins with array configuration not found when using `npx`
Hello!

## Current behavior

I'm using a shared configuration in an npm package that contains a plugin that is configured with the array form:
```
["@semantic-release/git", {
          "assets": ["package.json"],
          "message": "chore(release): ${nextRelease.version} [skip ci]\n\n${nextRelease.notes}"
      }]
```
And when I run everything with `npx`, it can't find the `@semantic-release/git` plugin:
```
[20:31:54] [semantic-release] › ✖  An error occurred while running semantic-release: { Error: Cannot find module '@semantic-release/git'
    at Function.Module._resolveFilename (module.js:547:15)
    at resolveFileName (/home/circleci/.npm/_npx/103/lib/node_modules/semantic-release/node_modules/resolve-from/index.js:29:39)
```

Note: the same happens with the `exec` plugin, I guess that there is something strange in the way the modules are resolved (also, this is working fine with 15.9).

## Expected behavior

Release is generated successfully

## Environment

- **semantic-release** version: 15.12.1
- CI environment: CircleCI
- Plugins used:
    "@semantic-release/commit-analyzer": "6.1.0",
    "@semantic-release/git": "7.0.5",
    "@semantic-release/github": "5.2.5",
    "@semantic-release/npm": "5.1.1",
    "@semantic-release/release-notes-generator": "7.1.4"

- **semantic-release** configuration:
```
module.exports = {
  "branch": "master",
  "plugins": [
      ["@semantic-release/commit-analyzer", {
          "releaseRules": [
              { "type": "ci", "release": "patch" }
          ]
      }],
      "@semantic-release/release-notes-generator",
      "@semantic-release/npm",
      "@semantic-release/github",
      ["@semantic-release/git", {
          "assets": ["package.json"],
          "message": "chore(release): ${nextRelease.version} [skip ci]\n\n${nextRelease.notes}"
      }]
  ],
  "preset": "angular"
};
```
- CI logs:
```
npx: installed 1477 in 22.866s
[20:31:54] [semantic-release] › ℹ  Running semantic-release version 15.12.1
[20:31:54] [semantic-release] › ✖  An error occurred while running semantic-release: { Error: Cannot find module '@semantic-release/git'
    at Function.Module._resolveFilename (module.js:547:15)
    at resolveFileName (/home/circleci/.npm/_npx/103/lib/node_modules/semantic-release/node_modules/resolve-from/index.js:29:39)
    at resolveFrom (/home/circleci/.npm/_npx/103/lib/node_modules/semantic-release/node_modules/resolve-from/index.js:43:9)
    at module.exports (/home/circleci/.npm/_npx/103/lib/node_modules/semantic-release/node_modules/resolve-from/index.js:46:41)
    at loadPlugin (/home/circleci/.npm/_npx/103/lib/node_modules/semantic-release/lib/plugins/utils.js:49:82)
    at options.plugins.castArray.reduce (/home/circleci/.npm/_npx/103/lib/node_modules/semantic-release/lib/plugins/index.js:17:37)
    at Array.reduce (<anonymous>)
    at module.exports (/home/circleci/.npm/_npx/103/lib/node_modules/semantic-release/lib/plugins/index.js:14:34)
    at module.exports (/home/circleci/.npm/_npx/103/lib/node_modules/semantic-release/lib/get-config.js:75:35)
    at <anonymous> code: 'MODULE_NOT_FOUND' }
{ Error: Cannot find module '@semantic-release/git'
    at Function.Module._resolveFilename (module.js:547:15)
    at resolveFileName (/home/circleci/.npm/_npx/103/lib/node_modules/semantic-release/node_modules/resolve-from/index.js:29:39)
    at resolveFrom (/home/circleci/.npm/_npx/103/lib/node_modules/semantic-release/node_modules/resolve-from/index.js:43:9)
    at module.exports (/home/circleci/.npm/_npx/103/lib/node_modules/semantic-release/node_modules/resolve-from/index.js:46:41)
    at loadPlugin (/home/circleci/.npm/_npx/103/lib/node_modules/semantic-release/lib/plugins/utils.js:49:82)
    at options.plugins.castArray.reduce (/home/circleci/.npm/_npx/103/lib/node_modules/semantic-release/lib/plugins/index.js:17:37)
    at Array.reduce (<anonymous>)
    at module.exports (/home/circleci/.npm/_npx/103/lib/node_modules/semantic-release/lib/plugins/index.js:14:34)
    at module.exports (/home/circleci/.npm/_npx/103/lib/node_modules/semantic-release/lib/get-config.js:75:35)
    at <anonymous> code: 'MODULE_NOT_FOUND' }Exited with code 1
```
