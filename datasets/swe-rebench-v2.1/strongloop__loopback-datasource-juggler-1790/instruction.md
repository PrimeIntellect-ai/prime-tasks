Model creation/replace misses rejected promise return on failure
<!-- 🚨 STOP 🚨 STOP 🚨 STOP 🚨

Are you using LoopBack version 4? Please report the bug here:
https://github.com/strongloop/loopback-next/issues/new

HELP US HELP YOU, PLEASE
- Do a quick search to avoid duplicate issues
- Provide as much information as possible (reproduction sandbox, use case for features, etc.)
- Consider using a more suitable venue for questions such as Stack Overflow, Gitter, etc.

Please fill in the *entire* template below.

-->

## Steps to reproduce
When trying to issue a model creation with `create` or replacement with `replaceById`, give data as input that would cause an error to be thrown.

## Current Behavior

<!-- Describe the observed result -->
The thrown error causes function execution termination and returns with the call of the original callback. However at that point of the execution it has not yet returned the created promise. So the promise remains unhandled and the function signature changes.

## Expected Behavior

<!-- Describe what did you expect instead, what is the desired outcome? -->
It should return the created promise which gets rejected.

## Link to reproduction sandbox

<!--
See https://loopback.io/doc/en/contrib/Reporting-issues.html#loopback-3x-bugs
Note: Failure to provide a sandbox application for reproduction purposes will result in the issue being closed.
-->

## Additional information

<!--
Copy+paste the output of these two commands:
  node -e 'console.log(process.platform, process.arch, process.versions.node)'
  npm ls --prod --depth 0 | grep loopback
-->
linux x64 12.13.0
loopback-datasource-juggler@4.14.0 /home/mitsos/Projects/loopback-datasource-juggler
├── loopback-connector@4.9.0
## Related Issues

<!-- Did you find other bugs that looked similar? -->

_See [Reporting Issues](http://loopback.io/doc/en/contrib/Reporting-issues.html) for more tips on writing good issues_

### Additional contract requirements

- `Model.create(data, [options], [callback])` is exposed as a static method on each model. When no callback is supplied, it returns a Promise that resolves with the newly created model instance. If a property setter throws while the instance is being initialised, that Promise is rejected with the error. When a callback is supplied, it is invoked asynchronously with the error.
- `Model.replaceById(id, data, [options], [callback])` is exposed as a static method on each model. When no callback is supplied, it returns a Promise that resolves with the updated model instance. If a property setter throws while the replacement attributes are being applied, that Promise is rejected with the error. When a callback is supplied, it is invoked asynchronously with the error.
