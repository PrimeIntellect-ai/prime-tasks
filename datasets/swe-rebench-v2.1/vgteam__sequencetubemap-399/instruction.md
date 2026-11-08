Get rid of the dataPath in the examples and tests
We no longer use the `dataPath` field on view targets, but it is still set on the examples in `config.js` and still checked in the link to view tests. We should get rid of it and only use the one global `dataPath`.

### Additional contract requirements

- The example view targets in `src/config.json` (the entries of the top-level `DATA_SOURCES` array) must not contain a `dataPath` field. Only the top-level global `dataPath` remains.
