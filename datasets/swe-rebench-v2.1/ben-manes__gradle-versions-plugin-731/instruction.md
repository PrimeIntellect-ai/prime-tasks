Only locally available included builds are shown as unresolved
I have build `A` with an included build `build-logic` that is a purely local included build without a published release.
The report show this as
```plain
Failed to determine the latest version for the following dependencies (use --info for details):
 - null:build-logic
The exception that is the cause of unresolved state: org.gradle.internal.resolve.ModuleVersionNotFoundException: Could not find any matches for null:build-logic:+ as no versions of null:build-logic are available.
Searched in the following locations:
  - https://repo.maven.apache.org/maven2/null/build-logic/maven-metadata.xml
Required by:
    project :
```

If such a dependency that has no version available at all is coming from an included build, then it would be nice if it would not be shown as unresolved, but probably as up-to-date or not at all.

### Additional contract requirements

- For dependencies without a group, expose the group as the empty string (`""`) in unresolved dependency selectors and undeclared coordinates.
