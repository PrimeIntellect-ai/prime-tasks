4.1 breaks on extending multiple configs from a plugin
**Tell us about your environment**

* **ESLint Version:** 4.1.0
* **Node Version:** 8.0.3
* **npm Version:** 5.0.3

**What parser (default, Babel-ESLint, etc.) are you using?**
default and typescript

**Please show your full configuration:**

<!-- Paste your configuration below: -->
```
{
  "plugins": [
    "@corbinu/corbinu"
  ],
  "extends": [
    "plugin:@corbinu/corbinu/base",
    "plugin:@corbinu/corbinu/node",
    "plugin:@corbinu/corbinu/lodash",
    "plugin:@corbinu/corbinu/relax"
  ],
  "rules": {
    "node/no-missing-require": "off"
  }
}
```

**What did you do? Please include the actual source code causing the issue.**
I upgraded to 4.1 and began seeing output as if "sourceType" was not set to module.

If I remove all the extends except for "plugin:@corbinu/corbinu/base" then things begin to resolve again or if I paste and merge the configs from each of those then everything reacts normally

Sorry know it makes it more complex to dig into my plugin the source is here: [https://gitlab.com/corbinu/eslint-plugin-corbinu](https://gitlab.com/corbinu/eslint-plugin-corbinu)

It is only a set of configs no rules of my own.

### Additional contract requirements

- When a configuration file's `extends` lists several different configurations from the same plugin (for example `plugin:test/foo` and `plugin:test/bar`), each of them must be loaded and merged into the effective configuration. Where entries conflict, the later entry takes precedence, as with other `extends` entries.
- The effective configuration must keep the `parserOptions.sourceType` value (for example `"module"`) that a plugin configuration sets, so the module setting is still in effect after the plugin configurations are merged.
