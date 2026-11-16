Add config option to ignore filepaths
<!---
Thank you for contributing an idea to this project!

Please see our [OSS process document](https://github.com/honeycombio/home/blob/main/honeycomb-oss-lifecycle-and-practices.md#) to get an idea of how we operate.
--->

**Is your feature request related to a problem? Please describe.**
The agent currently looks at every file in the container `/var/log` directory to generate events. This is a problem when something (like log rotation) creates a copy of the log file with another extension (like `tmp`), because that results in the agent scanning all the same log lines again, and creating duplicate events. As a side effect, this scenario also manifests in what appears as huge event ingest latency in Honeycomb, because the agent is scanning log lines that happened hours prior.

**Describe the solution you'd like**
Allow users to configure ignored file paths, so they can ignore temp files, as well as compressed files, since those cannot be parsed and result in errors in the agent log.

**Describe alternatives you've considered**
We can just add a warning to the docs to be wary of log rotation, but we don't have a good workaround at this time short of disabling log rotation.

**Additional context**
[internal asana](https://app.asana.com/0/526085303034087/1201979509997282/f)

### Additional contract requirements

The watcher configuration accepts an `exclude` key whose value is a list of glob patterns (Doublestar syntax) identifying file paths to ignore. The watcher configuration type in package `config` has a public field `ExcludePaths []string` that holds the patterns configured under the `exclude` key.

Add a function `determineFilterFunc(pod *v1.Pod, basePath string, containerName string, legacyLogPaths bool, excludePaths []string) func(fileName string) bool` in package `podtailer`. It returns a predicate that reports whether a full file path should be included; a nil return means no filtering is required. The predicate applies container-name matching and, when `excludePaths` is non-empty, excludes files matching any of those glob patterns (Doublestar syntax).

Add a function `doublestarGlob(pat string) ([]string, error)` in package `tailer`. It resolves a glob pattern (including `**` recursive matches) against the filesystem and returns the matching file paths, preserving `filepath.Glob` behavior for simple patterns.
