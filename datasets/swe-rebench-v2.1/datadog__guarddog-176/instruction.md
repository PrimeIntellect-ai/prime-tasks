NPM: not detecting postinstall scripts
Hello team! Very cool tool you have created, and I am glad for the NPM support!

When testing this tool against different malicious packages I get no results, I took som examples from https://github.com/spaceraccoon/npm-zoo

For example:
https://github.com/spaceraccoon/npm-zoo/tree/master/packages/pizza-pasta/pizza-pasta-1.0.3
```
guarddog npm scan package.json
Found 0 potentially malicious indicators scanning package.json
```

```
guarddog npm verify package.json
Scanning using at most 16 parallel worker threads
```

Should this one be detected, or am not running the correct commands?

Cheers,

emil

### Additional contract requirements

- The identifier `.` must be treated as a local target, so that
  `guarddog <ecosystem> scan .` scans the local current directory instead of
  attempting to fetch a remote package named `.`.
- Scanning the local current directory must run the source-code analysis rules,
  so that a postinstall script present in the scanned tree is reported (for
  example, `guarddog npm scan .` reports the `npm-install-script` finding).
