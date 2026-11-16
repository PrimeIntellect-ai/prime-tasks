.smart() cause unwanted loader sequence
as loaders are run with the loaders array ascendingtly, smart merging reverse the config merging order, that would break some loader overload functionality.

### Additional contract requirements

- The package's main module `lib/index.js` exports a function `merge(...configs)` that merges one or more webpack configuration objects into a single configuration object.
- `merge` exposes a `smart` method, `merge.smart(...configs)`, which performs the smart merge described above.
- Both merges combine the supplied configurations in the order they are given: loader entries contributed by an earlier configuration appear before loader entries contributed by a later configuration (new loaders are appended after existing ones).
- Loader-related configuration keys are `preLoaders`, `loaders`, and `postLoaders`.
- The smart merge combines loader entries that share the same `test` value: their loader lists are appended (the later configuration's loaders come after the earlier ones), and when the same loader name appears again its query string is replaced by the latest value.
- When two loader entries share the same `test`, the smart merge combines them, except that if the later entry specifies an `include` (or `exclude`) value that differs from the earlier entry's, the two entries are kept as separate entries.
