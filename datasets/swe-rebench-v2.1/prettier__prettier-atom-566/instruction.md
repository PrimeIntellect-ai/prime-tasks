Can't update to or install v0.58.1
I saw there was an update available and used the atom ui to update the package but it failed and showed this error:

```
Installing “prettier-atom@0.58.1” failed.Hide output…

npm ERR! Invalid dependency type requested: alias

npm ERR! A complete log of this run can be found in:
npm ERR!     /Users/akonwi/.atom/.apm/_logs/2019-11-04T20_21_05_062Z-debug.log
```

I uninstalled the package completely and attempted to just install the latest version and I get the same result and error.

### Additional contract requirements

- The package must not declare any dependency using the npm alias protocol (a version specifier of the form `npm:<package>@<version>`), because the Atom package manager rejects it with `Invalid dependency type requested: alias`.
- The prettier-eslint integration must use the `@lewisl9029/prettier-eslint` package.
