ForceExclude
# This is a Feature Proposal

## Description

Under the current method for bundling externals, while you can exclude dependencies by marking them as devDependencies, if a downstream dependency re-includes it, it will be bundled regardless.

While 99% of the time this makes sense, there are still a lot of projects out there, that are not lambda exclusive, which include `aws-sdk` as a dependency. While I could ask every project maintainer to move aws-sdk to peerDependency or devDependency - I think adding a `forceExclude` would be a simple fix for a wide(ish) problem

i.e.
```
webpackIncludeModules:
    forceInclude:
      - module1
      - module2
    forceExclude:
      - aws-sdk
      - module2
```

### Additional contract requirements

When a module appears in both `forceInclude` and `forceExclude`, it must not be packaged; `forceExclude` takes precedence.
