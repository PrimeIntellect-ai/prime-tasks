bom-ref missing when passing project name and version via cli args
When passing `--project-name some/repo --project-version some-version` via the cli, the `bom-ref` attribute is not populated.  This causes Dependency Track to not create a dependency graph for the project.

Removing these two cli args however will populate a `bom-ref` and the dependency graph.

### Additional contract requirements

- Add a public function `parsePkgLock(pkgLockFile, options = {})` in module `utils.js`. It parses a Node.js `package-lock.json` (lockfile version 1, 2, or 3) and resolves to an object containing `pkgList` (component descriptors, each with a generated `bom-ref`) and `dependenciesList` (dependency relationships).
- `options.projectName` (string) overrides the root package name.
- `options.projectVersion` (string) overrides the root package version.
- `options.projectGroup` (string) overrides the root package group.
- When project metadata is supplied, the root component `bom-ref` is generated from that metadata.
