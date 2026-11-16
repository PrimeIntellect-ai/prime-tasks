Asynchronous configuration object support for Webpack
# This is a  Feature Proposal

## Description
Webpack 2+ support async configuration object by exporting a promise as configuration object.
This is a feature request to support async configuration object. This feature helps to define env variables and constants inside code after an async operation inside `webpack.config.js`. for example defining `AccountId` of current user inside `lambda@edge` which does not support defining normal process environment variables.

Similar or dependent issue(s):

## Additional Data

* ***Serverless-Webpack Version***: 5.1.5
* ***Webpack version***: 4.11.1
* ***Serverless Framework Version***: 1.27.2
* ***Operating System***: MacOS High Sierra (10.13.5)
* ***Stack Trace***:

### Additional contract requirements

- The webpack configuration may be exported as a promise, the result of an async function, or any thenable (an object exposing a callable `then` method). The plugin awaits it and processes the resolved configuration object.
- A resolved asynchronous configuration is processed exactly like a synchronous one: missing defaults are applied for `context` (the service path), `target` (`node`) and `output` (`{ libraryTarget: 'commonjs', path: <servicePath>/.webpack/service, filename: '[name].js' }`), and individual-package handling is applied when `package.individually` is set.
- If the exported promise/thenable rejects, `validate()` rejects with the rejection reason.
- When `package.individually` is set, the resolved configuration is expanded into one configuration per function, each preserving the other configuration options and nesting its `output.path` under the function name.
