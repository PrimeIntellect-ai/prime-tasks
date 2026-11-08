Add cli argument to skip dependencies packaging
In some scenarios people tend to compile dependencies by their own before doing `oc publish`, so let's add a cli argument, something like `--skip-dependencies` or `--skip-build`, to allow us skip the dependencies installation later again via oc.

### Additional contract requirements

- The `publish` CLI command must expose a boolean option named `--skipPackage` (default `false`), so that `oc publish --skipPackage <componentPath>` skips dependency installation or build work that would otherwise be performed.
- With `--skipPackage` enabled, the publish command must continue publishing the component package that was prepared by the user.
