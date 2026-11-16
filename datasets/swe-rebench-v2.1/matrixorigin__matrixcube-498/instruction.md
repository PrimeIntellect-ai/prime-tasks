Add matrixone_test build tag
When build with the matrixone_test tag, extra types and methods can be included into the build. They would be mostly used in tests.

This allows us to provide extra exported methods and types just for our tests without any impact on our production build.

### Additional contract requirements

When built with the `matrixone_test` build tag, `raftstore` provides an exported `LogDBGetter` interface with a `GetLogDB() logdb.LogDB` method, and a store implements that interface to expose its associated LogDB (which may be nil). The test-only accessor must not be required or included by the production build without that tag.
