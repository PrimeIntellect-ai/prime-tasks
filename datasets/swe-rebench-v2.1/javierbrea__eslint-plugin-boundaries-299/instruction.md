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

- The `external` rule accepts a `path` option on a module matcher: `[<module pattern>, { path: <string | string[]> }]`. The path is the part of the import that follows the base module name and starts with `/`. The matcher matches when at least one of the supplied micromatch patterns matches the path.
- Path matcher patterns support the same captured element-template value substitutions as other patterns in the `external` rule.
- Custom error messages in the `external` rule support the `${report.path}` placeholder. It is replaced with the matched path, so a message `"Do not import ${report.path} from RDD"` renders as `"Do not import /var/foo from RDD"` when the matched path is `/var/foo`.
