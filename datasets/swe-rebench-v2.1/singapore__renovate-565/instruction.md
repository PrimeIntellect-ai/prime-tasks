Attempted lookup of git+ssh dependency
This github dependency: https://github.com/joefraley/babel-preset-meridian/blob/master/package.json#L44

is producing the following warning:
```json
{
    "repository": "joefraley/babel-preset-meridian",
    "packageFile": "package.json",
    "depType": "devDependencies",
    "dependency": "eslint-config-meridian",
    "level": 40,
    "msg": "Failed to look up dependency",
}
```

It shouldn't be looked up in the first place.
