Add human-readable list output
Currently we only have JSON. Allow for yaml and human-readable like
our other outptus

### Additional contract requirements

- Add a public function `PrintVersionList(outputFormat string) error` in package `pkg/api`. It accepts the output formats `normal`, `wide`, `json`, and `yaml`. It writes the global `VersionList` to standard output in the requested format, returning `nil` on success and an error describing the failure otherwise (for example, when the requested format is not one of the supported formats).
- Add a function `printVersionsTabular() error` in package `pkg/api`. It renders the global `VersionList` as a formatted table to standard output with columns for Kind, Name, Deprecated-In, Removed-In, and Replacement, and returns an error if the table cannot be written to standard output.
