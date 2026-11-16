Support excluding files from a configuration file
As of now `usort` does not provide an option to exclude certain files from a configuration file. There is the `# usort:skip` (or `# isort:skip`) directive, but this gets tedious fast if one wants to skip a complete directory or files based on a pattern.

There are several options from other formatters / linters how to achieve this. Since `usort` should be used with a code formatter and `black` is an obvious choice, IMO it would be a good idea to [HIDDEN]

### Additional contract requirements

- The `excludes` configuration option is a list of gitignore-style filename patterns
  (the same syntax used in `.gitignore` files), not regular expressions.
- `usort_path` omits any file or directory whose path matches a configured `excludes`
  pattern, in addition to files matched by the project's `.gitignore`.
