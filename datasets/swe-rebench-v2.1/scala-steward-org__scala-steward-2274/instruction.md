Add --disable-default-artifact-migrations flag to prevent needing external connection
The existing flag:

```
  --disable-default-scalafix-migrations  BOOLEAN     Wether to disable the default scalafix migration file
```

prevents a call out to raw.githubusercontent.com as part of Scala Steward running. I'd like to add the equivalent for artifact migrations:

```
  --disable-default-artifact-migrations  BOOLEAN     Whether to disable the default artifact migrations file
```

This would allow scala-steward to run inside environments where all external network access needs to be whitelisted, without having to whitelist raw.githubusercontent.com

### Additional contract requirements

- The application configuration exposes the artifact migration settings as `artifactCfg: ArtifactCfg`. `ArtifactCfg` is defined in `org.scalasteward.core.application.Config` as `ArtifactCfg(migrations: List[Uri], disableDefaults: Boolean)`. When `--disable-default-artifact-migrations` is set, `disableDefaults` is `true`; otherwise it is `false`.
- `ArtifactMigrationsLoader.loadAll(config: ArtifactCfg)` returns `F[List[ArtifactChange]]`. It loads the built-in default artifact migration file unless `config.disableDefaults` is `true`, loads every file listed in `config.migrations`, and returns the combined list. It fails if any file cannot be parsed.
