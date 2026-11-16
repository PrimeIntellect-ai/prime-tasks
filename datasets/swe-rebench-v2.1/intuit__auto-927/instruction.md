Maven release multiple tags for the same release
**Describe the bug**
Given release `1.0.0`, during the maven plugin release we create tag  `v1.0.0`. However during the post step in `auto.loadDefaultBehavior` auto pushes release notes to tag `1.0.0`. This is due to `newVersion` missing the prefix. [HIDDEN]
https://github.com/intuit/auto/blob/master/plugins/maven/src/index.ts#L141-L142
``` javascript
await execPromise('mvn', [
        '-B',
        'release:prepare',
        `-Dtag=v${newVersion}`,
        `-DreleaseVersion=${newVersion}`,
        '-DpushChanges=false'
      ]);
```

<!-- A clear and concise description of what the bug is. -->

**To Reproduce**

execute maven plugins, it will result in two tags for the same release. `v1.0.0`, `1.0.0`

**Expected behavior**

<!-- A clear and concise description of what you expected to happen. -->

**Screenshots**

<!-- If applicable, add screenshots to help explain your problem. -->

**Desktop (please complete the following information):**

- OS: [e.g. iOS]
- Browser [e.g. chrome, safari]
- Version [e.g. 22]

**Additional context**

<!-- Add any other context about the problem here. -->

### Additional contract requirements

- For a Maven release, the tag used for release notes must match the prefixed Maven release tag, so the release does not create an unprefixed duplicate tag.
