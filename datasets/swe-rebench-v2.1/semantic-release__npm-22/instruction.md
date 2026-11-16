Preserver `package.json` formatting
Using `readJson` and `writeJson` from `fs-extra` remove the JSON formatting and write the `package.json` as one long string.

It's a problem for plugins like `git` that publish the `pacakge.json`

### Additional contract requirements

- When updating an existing `npm-shrinkwrap.json`, preserve its text exactly except for replacing the version value with the requested version.
