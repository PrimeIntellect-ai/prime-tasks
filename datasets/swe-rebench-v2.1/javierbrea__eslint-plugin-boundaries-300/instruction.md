Matching paths in external modules
Thanks a lot for this plugin - it has been very useful so far.
I have a question though related to the following usecase:

We are moving some elements to a shared library and would like to enforce the same rules, that we have inside the sources, e.g. from: "components", disallow: "repositories".

This is what I came up with so far - which is not working:

```
    "boundaries/external": [
      "error",
      {
        default: "allow",
        rules: [
          {
            from: ["components"],
            disallow: ["@group/package/repositories/*"],
          },
        ],
      },
    ],
```

Is there any way to specify the allowed paths in a module?

### Additional contract requirements

The `boundaries/external` rule must support matching the path of an imported external module.

- Each entry of the `allow` and `disallow` arrays may be an array `[<module pattern>, <options>]`, where `<options>` is an object that may contain a `path` property in addition to `specifiers`.
- `path` is either a micromatch pattern string or an array of micromatch pattern strings.
- The import path of an external module is the module specifier with the base module name removed. For example, importing `react-router-dom/var/foo` has base module `react-router-dom` and import path `/var/foo`.
- When a rule entry provides `path`, the entry matches an import only if the import path matches at least one of the given patterns.
- The matched import path is available to custom error messages as `${report.path}`.
- When a rule entry with `path` matches and no custom message is configured, the default message reports the matched path using the same `Usage of '<report>' from external module '<baseModule>' <fileReport>` format used for specifier matches.
