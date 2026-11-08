HerdDB Collections  - do not perform Files#createDirectories at every page write
Under heavy load (frequent index page writes) Files#createDirectories adds too much overhead on the FS.

We can simply ensure that the directory for an index or for a page exists at boot and fail in case is is removed during server execution.

### Additional contract requirements

- `herddb.file.FileDataStorageManager` must expose public methods `initIndex(String tableSpace, String uuid)` and `initTable(String tableSpace, String uuid)`, both returning `void` and declaring `herddb.storage.DataStorageManagerException`. `initIndex` creates the directory hierarchy used to store the pages of the given index, and `initTable` creates the directory hierarchy used to store the pages of the given table, so that the corresponding directory exists before any page is written.
