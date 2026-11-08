Strict mode warning still refers to NODE_ENV variable even if overriding with NODE_CONFIG_ENV is used
When environment is overwritten via NODE_CONFIG_ENV, warning message should also consider this.

**Given:**
app is launched as
`NODE_CONFIG_ENV=ut NODE_ENV=production node index.js`
no configuration file at path _config/ut.json_

**Actual message in console:**
`WARNING: NODE_ENV value of 'ut' did not match any deployment config file names.`

**Expected message:**
`WARNING: NODE_CONFIG_ENV value of 'ut' did not match any deployment config file names.`

### Additional contract requirements

- In strict mode, when `NODE_CONFIG_ENV` is `local`, the exception message must be exactly `FATAL: NODE_CONFIG_ENV value of 'local' is ambiguous. See https://github.com/lorenwest/node-config/wiki/Strict-Mode`. When `NODE_CONFIG_ENV` is `cloud` and no matching deployment config file exists, the exception message must be exactly `FATAL: NODE_CONFIG_ENV value of 'cloud' did not match any deployment config file names. See https://github.com/lorenwest/node-config/wiki/Strict-Mode`.
