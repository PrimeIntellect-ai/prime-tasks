generateNotes doesn't accept multiple plugins from CLI
It appears that when [`generateNotes` was updated to be a "multi plugin" (like `verify-release`) in 15.7.0](https://github.com/semantic-release/semantic-release/commit/5989989), the CLI configuration was overlooked:

```js
    [HIDDEN]
```

https://github.com/semantic-release/semantic-release/blob/caribou/cli.js#L27

### Additional contract requirements

- The `--generate-notes` command-line option accepts multiple plugin names, like the other multi-plugin options. Supplying several values after the flag (for example `--generate-notes notes1 notes2`) must be accepted.
- The resulting `generateNotes` option is an array of the supplied plugin names in order (for example `['notes1', 'notes2']`), rather than a single string.
