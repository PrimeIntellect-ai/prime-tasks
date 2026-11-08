Add custom meta information with bt-cli
<!--
When trying to solve more solutions with Build Tracker, please keep in mind some of the following goals of the project:
* Be lightweight: small project size (single-digit KiBs, gzipped)
* Be easy: too many options in an API can become confusing
* Be clear: the intended purpose of every method should be as obvious as possible
* Is it easy to do this in "userland"? Would it be better off done there?
-->

# Problem

I want to add some custom Meta information to Builds. There is no option for this.

# Solution

* add `--meta` option to `bt-cli create-build` and `upload-build` commands. The value should be either a string-value or a JSON-encoded [BuildMetaItem](https://buildtracker.dev/docs/packages/build#buildmeta)

### Additional contract requirements

- The `--meta` value is a JSON-encoded object. Its entries are merged into the build's `meta` object in addition to the automatically detected fields (such as `revision`, `branch`, `timestamp`, `author`, `subject`, and `parentRevision`). Each entry value may be a plain string or an object of the form `{ "url": string, "value": string }`.
