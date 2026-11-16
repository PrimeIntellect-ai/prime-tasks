nyc@14 fails with error: Cannot read property 'children' of undefined
<!--Please use the template provided below when reporting bugs:-->
## Link to bug demonstration repository
<!--
A demo repository will show the combination of module versions being used,
command-lines and configurations.  NYC is very complex, it is difficult or
even impossible to triage most bugs without this information.

If you cannot share a link to your repository (maybe it's private) then you must
create a basic `nyc-bug-demo` repository and link to that please [mandatory].
-->
https://github.com/clementallen/smithers/tree/greenkeeper/nyc-14.0.0

MR with failing travis build: https://github.com/clementallen/smithers/pull/93

Failing build log: https://travis-ci.org/clementallen/smithers/jobs/520704518

## Expected Behavior
Coverage should run with no errors

## Observed Behavior
The following error occurs:
```
/www/smithers/node_modules/nyc/index.js:440
      if (parentInfo.children.indexOf(info.uuid) === -1) {
                     ^

TypeError: Cannot read property 'children' of undefined
    at infos.forEach.info (/www/smithers/node_modules/nyc/index.js:440:22)
    at Array.forEach (<anonymous>)
    at NYC.writeProcessIndex (/www/smithers/node_modules/nyc/index.js:437:9)
    at /www/smithers/node_modules/nyc/bin/nyc.js:68:9
    at ChildProcess.<anonymous> (/www/smithers/node_modules/foreground-child/index.js:52:5)
    at ChildProcess.emit (events.js:189:13)
    at maybeClose (internal/child_process.js:970:16)
    at Process.ChildProcess._handle.onexit (internal/child_process.js:259:5)
```

### Troubleshooting steps
- [x] still occurring when I put `cache: false` in my nyc config

## Environment Information
<!--
[mandatory] run the following script: npx envinfo@latest --preset nyc
-->
```
  System:
    OS: macOS Mojave 10.14.4
    CPU: (4) x64 Intel(R) Core(TM) i5-6360U CPU @ 2.00GHz
    Memory: 156.02 MB / 8.00 GB
  Binaries:
    Node: 10.15.3 - ~/.nvm/versions/node/v10.15.3/bin/node
    npm: 6.4.1 - ~/.nvm/versions/node/v10.15.3/bin/npm
  npmPackages:
    @babel/cli: ^7.4.3 => 7.4.3
    @babel/core: ^7.4.3 => 7.4.3
    @babel/polyfill: ^7.4.3 => 7.4.3
    @babel/preset-env: ^7.4.2 => 7.4.2
    @babel/register: ^7.4.0 => 7.4.0
    babel-plugin-add-module-exports: ^1.0.0 => 1.0.0
    nyc: ^14.0.0 => 14.0.0
```

### Additional contract requirements

- For a recursively nested nyc invocation, the command must exit with status 0 and leave both stdout and stderr empty.
