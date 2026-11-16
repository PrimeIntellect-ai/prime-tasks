Environment variables do not override INI values

### Additional contract requirements

- When no project name is available (neither the `name` argument nor a
  `cliquet.project_name` setting value), the function emits a warning whose
  message is exactly `No value specified for \`project_name\``.
