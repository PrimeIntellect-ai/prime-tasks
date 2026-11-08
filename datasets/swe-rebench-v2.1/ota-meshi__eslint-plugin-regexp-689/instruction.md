Add option to rule `no-unused-capturing-group` to allow unused named capturing groups
### Motivation

I have this regex:

```javascript
const REGEX_SEMANTIC_VERSION = /(?<majorVersion>\d+)\.(?<minorVersion>\d+)\.(?<patchVersion>\d+)(?:-(?<suffix>.+))?/;
```

The named capturing groups makes it clear what part of the regex is what.
Currently I don't access these capturing groups, so [`no-unused-capturing-group`](https://ota-meshi.github.io/eslint-plugin-regexp/rules/no-unused-capturing-group.html) reports this as an error.

### Feature Request

Add an option to `no-unused-capturing-group` so that it does not report unused named capturing groups.

### Additional contract requirements

- Set the option to `{ allowNamed: true }` to suppress reports for unused named capturing groups.
- Unused unnamed capturing groups must still be reported when this option is enabled.
