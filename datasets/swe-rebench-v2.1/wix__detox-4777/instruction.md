Replace tempfile with something like tempy
### Describe your idea

Currently, Detox relies on `tempfile`, which relies on `uuid@3.4.0`. On running `npm i` this generates a warning. Checking the `tempfile` repo it hasn't been updated since last year, and the README recommends switching to the `tempy` package.

### Additional contract requirements

- The `detox` package must no longer list `tempfile` as a dependency; it must list `tmp` as the replacement dependency.
- Add a public function `tempfile(extension?)` in module `detox/src/utils/tempfile.js` that returns a string path to a newly generated temporary file.
- The returned path follows the pattern `detox-<pid>-XXXXXX[.extension]`, where `<pid>` is the current process id.
- The optional `extension` argument may be supplied with or without a leading dot; the resulting path contains exactly one leading dot before the extension. If the extension is omitted or empty, no extension is added.
- Generated temporary files are removed when the process exits.
