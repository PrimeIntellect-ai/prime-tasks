Prettify DependencyOutdated log statement
Hello there ✋ ,

Could we please prettify the log statement below because it's currently very verbose and hard to understand?

Cheers 🍺

```
DependencyOutdated(CrossDependency(NonEmptyList(Dependency(io.dropwizard.metrics,ArtifactId(metrics-core,None),3.2.6,None,None,None))),Single(CrossDependency(NonEmptyList(Dependency(io.dropwizard.metrics,ArtifactId(metrics-core,None),3.2.6,None,None,None))),NonEmptyList(4.1.5),None))
```

### Additional contract requirements

- Add a public function `show(updateState: UpdateState): String` in `org.scalasteward.core.update.data.UpdateState` that returns a concise, human-readable one-line summary of the given state.
- The summary includes the dependency's group id, artifact names and current version, formatted as `groupId:artifactNames : version`. When a cross-dependency contains several artifacts, their names are listed together as `(name1, name2, ...)`.
- An up-to-date dependency is summarized as `up-to-date: groupId:artifactNames : version`.
- An outdated dependency is summarized as `new version: groupId:artifactNames : version -> newerVersion`.
- A pull-request state is summarized with a status label followed by the version information and the pull request URI in parentheses: `PR opened: groupId:artifactNames : version -> newerVersion (pullRequest)`, `PR outdated: ...`, and `PR closed: ...`.
- The message logged for a repository with outdated dependencies contains, for each outdated state, the concise summary described above rather than the default representation of the state.
