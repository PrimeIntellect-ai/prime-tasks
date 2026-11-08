Enable makeAlbums to use more than the last component of the folder name
When a lot of photos are being shared, the last component of a file path can collide (e.g. 2018/Christmas with 2019/Christmas).

GooglePhoto does not support hierarchical structures. Concatenating path elements would probably work for many use case (e.g. 2018_Christmas and 2019_Christmas or 2018/Christmas and 2019/Christmas).

### Additional contract requirements

The album naming strategy is selected through the `makeAlbums.use` configuration option. Its accepted values are `folderPath` (use the whole folder hierarchy) and `folderName` (use only the immediate folder name). When albums are enabled, the album created for an uploaded item must use the configured strategy.

Add the following functions in package `upload`:

- `albumNameUsingTemplate(path string, template string) string`: returns the album name for `path` according to `template`. `"folderPath"` uses the whole folder hierarchy, `"folderName"` uses only the immediate folder name, and any other value returns an empty string.
- `albumNameUsingFolderPath(path string) string`: returns the directory part of `path` with `/` replaced by `_` (for example `foo/bar/` gives `foo_bar`). Returns an empty string when `path` has no parent directory.
- `albumNameUsingFolderName(path string) string`: returns the base name of the parent directory of `path` (for example `foo/bar/file` gives `bar`). Returns an empty string when `path` has no parent directory.
- `NewJobOptions(createAlbum bool, albumNameStrategy string, deleteAfterUpload bool, filter *Filter) *JobOptions`: builds the options for a folder upload job. `albumNameStrategy` is the selected album naming strategy (`folderPath` or `folderName`).
- `(*Job).ScanFolder(logger log.Logger) ([]Item, error)`: scans the job's source folder and returns the items to upload, creating the album for each item according to the configured strategy.

Add the following function in package `utils/filesystem`:

- `RelativePath(basepath string, path string) string`: returns `path` relative to `basepath` when `path` is located under `basepath`; otherwise returns `path` unchanged. The returned path never climbs above `basepath`.
