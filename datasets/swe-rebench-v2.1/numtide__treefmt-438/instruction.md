treefmt 2+ no longer formats gitignored files passed explicitly as arguments
**Context**

I believe treefmt 1.x was totally ignorant of VCS/git, and would happily format all files it could find (including stuff the `.git` directory!).

It's great that treefmt 2+ doesn't do this: it's default filesystem walker ("auto") detects when we're in a git repo and ignores untracked files.

**Describe the bug**

The problem is that treefmt no longer formats files that are explicitly passed as arguments.

This breaks my "generic nix fmt" formatter I wrote for null-ls/none-ls. See https://github.com/jfly/snow/blob/835b3765b2fa18768ccebb474b292c061ba47752/pkgs/neovim/vimrc#L332-L342. Much like treefmt itself, under the hood, null-ls generates tempfiles and passes them as command line parameters to the formatter. It expects the formatter to format these files, even though they're not tracked by git.

In other words, null-ls expects formatters to obey [treefmt's formatter specification](https://github.com/numtide/treefmt/blob/v2.0.5/docs/formatter-spec.md). (On a related note, I've tried to clarify this here: https://github.com/numtide/treefmt/pull/434). I'd argue that treefmt itself doesn't follow its own formatter specification, because it won't format untracked tempfiles.

(I am aware of treefmt's `--walk=filesystem` parameter, but that would require my null-ls plugin to somehow know that it's invoking treefmt, when all it really knows is that it's invoking `nix fmt`.)

**Expected behavior**

I'd like for treefmt's default behavior to be to format files passed explicitly on the command line, even if those files are not tracked by git. If folders are passed, or if `--walk=git` is used, it's fine to apply the normal filesystem walking rules.

### Additional contract requirements

- Add a public function `NewFilesystemReader(root string, path string, statz *stats.Stats, batchSize int) *FilesystemReader` in the `walk` package. It walks the given relative path; an empty path defaults to the tree root.
- Add a public function `NewGitReader(root string, path string, statz *stats.Stats, batchSize int) (*GitReader, error)` in the `walk` package. It enumerates the files tracked in the git index under the given relative path; an empty path defaults to the tree root.
- Add a public method `(*File).Release() error` in the `walk` package. It runs the release callbacks registered on the file and returns the error returned by a callback, or nil if none fail.
- Add a public method `(*File).AddReleaseFunc(fn ReleaseFunc)` in the `walk` package, where `ReleaseFunc` is the exported named function type `func() error`, to register a release callback on a file.
