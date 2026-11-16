Working directory unexpectedly set to wherever noxfile.py is.
<!-- Thank you for filing a bug! Please feel free to answer as much or as little of this template as you can. -->

**Describe the bug**
Trying to invoke nox from a different folder using the --noxfile flag sets the current working directory to where the noxfile lives.  This makes reusing a noxfile across multiple projects in a monorepo very difficult, since I can't find a good way to set the current working directory to where nox was called from.  Even passing '.' as a posarg will end up being interpreted as the directory where the noxfile lives

**Expected behavior**
Either the cwd stays as wherever nox is called from, or we have some command line arg for what to treat as the cwd.  If this feature already exists and I've missed it, or there are some other recommendations for how to use a single nox file across multiple projects, please let me know!

### Additional contract requirements

- The global options namespace produced by `nox._options.options.namespace()` includes an `invoked_from` value that defaults to `os.getcwd()` and records the directory from which Nox was originally invoked.
- `nox.sessions.Session` exposes an `invoked_from` property that returns the directory from which Nox was originally invoked.
- An option can be created with `hidden=True`; hidden options are omitted from the argument parser and receive their default values after parsing, and they may have no group.
- A non-hidden option that has no group causes `nox._option_set.OptionSet.parser()` to raise `ValueError`.
