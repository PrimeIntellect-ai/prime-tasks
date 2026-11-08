semantic-release throws on array of analyzeCommits plugins
## Current behavior

semantic-release throws an error if array of `analyzeCommits` plugins are present in config.

## Expected behavior

semantic-release supports multiple `analyzeCommits` or displays error message which clarifies on that only single plugin is supported.

## Environment

- **semantic-release** version: 15.8.1
- **@semantic-release/commit-analyzer** version: 6.0.0
- CI environment: any
- **semantic-release** configuration:
```js
{
  analyzeCommits: [
    { path: '@semantic-release/commit-analyzer' },
  ]
}
```
- CI logs:
```
The analyzeCommits plugin configuration (https://github.com/semantic-release/semantic-release/blob/caribou/docs/usag
e/plugins.md#analyzecommits-plugin) if defined, must be a single or an array of plugins definition. A plugin definition is either a string or an object with a path property.

Your configuration for the `analyzeCommits` plugin is `[ { path: '@semantic-release/commit-analyzer' } ]`
```

---

Hey there 👋

I believe this is a regression since [this change](https://github.com/semantic-release/semantic-release/commit/49f5e704ba0670cebff41853e29a747d93af0874#diff-205c5cf625514dcf92e20a30d112c1cdR16). `configValidator` for `analyzeCommits` doesn't check for an array, like other plugins do. Not sure if error message needs to be tweaked, or logic of config validator itself.

### Additional contract requirements

- Add a public function `validateConfig(typeInfo, conf)` in module `lib/plugins/utils.js`. `typeInfo` is an object with two boolean properties: `multiple` (`true` when the plugin may be supplied as a single definition or an array of definitions, `false` when only a single definition is allowed) and `required` (`true` when the plugin must be present in the configuration, otherwise it is optional). `conf` is the user-provided configuration for the plugin and may be `undefined`, `null`, a string (module path), a function (inline plugin), an object with a `path` property, or an array containing any combination of those values. The function returns `true` when the supplied configuration satisfies the requiredness and multiplicity rules and every definition is a valid plugin definition (a string, an object with a string `path`, or a function), and `false` otherwise. A top-level `undefined` or `null` configuration is treated as absent: it is valid for an optional plugin and invalid for a required plugin.
- When a plugin configuration is rejected, the resulting `EPLUGINCONF` error message must clarify that the plugin accepts only a single definition, by stating that the configuration must be a single plugin definition.
