The `--no-ci` option is ignored
## Current behavior

When calling `semantic-release --no-ci`, the parameter is ignored.
`commander` set `options.noCi` as `undefined`, instead the `options.ci` is set to `true`.

[HIDDEN] So `noCi` from a config file is effectively ignored.

## Expected behavior

`semantic-release --no-ci` should be parsed properly.

### Additional contract requirements

- When a run is triggered by a pull request and `noCi` is not set, `semanticRelease` returns a falsy value and logs the message `This run was triggered by a pull request and therefore a new version won't be published.` The position of this message among the logger calls is not significant.
- The `--no-ci` option must allow a release to be published during a non-CI run.
- A `noCi` option set in a configuration file (for example `.releaserc.json`) must be honoured during a non-CI run, allowing the release to be published just like the equivalent API or CLI option.
