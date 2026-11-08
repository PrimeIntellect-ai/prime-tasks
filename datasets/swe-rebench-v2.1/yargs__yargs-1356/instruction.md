Replace os-locale with inline code
Due to yargs passing `spawn: false` to os-locale most of the functionality of that module is unused.  The following could be used as a drop-in replacement for os-locale:

[HIDDEN]

The benefit is a large drop of production dependencies.  Currently a project with `yargs` as the only dependency installs 53 modules / 1.8MB to node_modules.  Without os-locale this becomes 26 modules / 1.1MB.  The size reduction is not my primary interest of this issue, the goal is cutting the number of modules that have to be audited in half.

### Additional contract requirements

- Yargs must not have `os-locale` as a production dependency.
- Locale detection must use the first available value in this order: `LC_ALL`, `LC_MESSAGES`, `LANG`, then `LANGUAGE`. If none is available, use `en_US`.
- The detected locale must exclude the first `.` or `:` and everything after it.
