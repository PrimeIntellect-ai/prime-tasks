Add glob collector
The directory collector is based on a regex (which also is flagged as case insensitive). I would really like to be able to use a glob pattern (maybe allow the non-php glob pattern dir/**/somethingDeeper).
As I understood it is possible to create custom collectors, but would you be interested in a PR adding a glob collector (and should it allow the double star)?

### Additional contract requirements

- Layer collectors support a collector type named `glob`. Its configuration has a `value` key holding a glob pattern, for example `value: src/Modules/**/Repository`.
- A file is selected by the `glob` collector when its path, relative to the directory that contains the configuration file (`deptrac.yaml`), matches the pattern. Files whose paths do not match are not selected.
- `*` matches any sequence of characters within a single directory level and does not cross `/`.
- `**` matches across any number of nested directory levels, so `foo/**/*.php` selects `foo/a/b/c/Thing.php` but not `bar/a/Thing.php` or `foo/Thing.txt`.
