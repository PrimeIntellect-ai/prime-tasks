Add link to .scala-steward.conf documentation to PRs
Recent PRs enhanced the capabilities of repo specific configuration via `.scala-steward.conf` (#1274, #1254, #1330, #1336). To increase the discoverability of these features, we could link to the [`.scala-steward.conf` documentation](https://github.com/fthomas/scala-steward/blob/master/docs/repo-specific-configuration.md) in PR bodies.

### Additional contract requirements

- The PR body must include this exact paragraph between the sentence ending “mention me in the comments below.” and “Have a fantastic day writing Scala!” (with `${BuildInfo.gitHeadCommit}` replaced by its value): `Configure Scala Steward for your repository with a [`.scala-steward.conf`](https://github.com/fthomas/scala-steward/blob/${BuildInfo.gitHeadCommit}/docs/repo-specific-configuration.md) file.`
