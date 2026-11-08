Support for `pipx inject <package> -r <requirements-file>`
**How would this feature be useful?**

I'd like to be able to inject packages into a package environment from a standard pip requirements file and have them registered individually as "injected" dependencies, e.g. for `list --include-injected` and `upgrade(-all) --include-injected`.

Alternatives listed below all have deficiencies in some way.

This is a different take on https://github.com/pypa/pipx/issues/359 and https://github.com/pypa/pipx/issues/357 (etc).

**Describe the solution you'd like**

As mentioned by @funkyfuture in https://github.com/pypa/pipx/issues/359#issuecomment-593279235.

```
pipx inject <package> -r <requirements-file>
```

**Describe alternatives you've considered**

The standard solution below is OK, but doesn't register the additional packages as "injected". Hence they're invisible to commands that support `--include-injected`.

```
pipx install <package>
pipx runpip <package> install -r <requirements-file>
```

The following solution by @Sispheor and @hanfried doesn't work on Windows, may miss edge-cases, and is generally clumsy.

```
cat <requirements-file> | sed -e 's/#.*//' | xargs pipx inject <package>
```

### Additional contract requirements

- `pipx inject` accepts the `--requirement <file>` option (which may be repeated) in addition to package specifiers given directly on the command line.
- The packages to inject are the combination of the command-line specifiers and the specifiers read from every requirement file. Each requirement-file line is a package specifier; a `#` comment is stripped from the line and empty lines are ignored.
- The combined list of package specifiers is deduplicated and sorted, and an INFO log message `Injecting packages: {specifications!r}` is emitted, where `{specifications!r}` is the Python list representation of the final sorted specifications.
