Failing to get fork name when the forked repository has a different name
A real example of this issue is:

PR https://github.com/apache/incubator-kie-kogito-apps/pull/1881 was opened for `apache/incubator-kie-kogito-apps` repository but the the fork name is https://github.com/elguardian/kogito-apps which is different from the repository name.

The checkout summary shows:
```
# Checkout summary
[INFO] [apache/incubator-kie-drools]
[INFO] 	 Project taken from apache/incubator-kie-drools:main (Branch HEAD 1deba3ffbd2a9de4ebfbf4c1bb0d57523b3f8ffb)
[INFO] [apache/incubator-kie-kogito-runtimes]
[INFO] 	 Project taken from apache/incubator-kie-kogito-runtimes:main (Branch HEAD 821650efe7688f55359611a190ed7f3e6026f05a)
[INFO] [apache/incubator-kie-kogito-apps]
[INFO] 	 Project taken from apache/incubator-kie-kogito-apps:main (Branch HEAD a9f5d1cb4bb0759ef63facd2b81c8c79da373a18)
[INFO] [apache/incubator-kie-kogito-examples]
[INFO] 	 Project taken from apache/incubator-kie-kogito-examples:main (Branch HEAD bc4d19e48b2a45409fb9e6db1638c993eacb6180)
```

Meaning that all branches from the forks were ignored and the and just the main branches are used.

### Additional contract requirements

- The fork-name lookup is exposed as a public method `getForkName(targetOwner: string, sourceOwner: string, repo: string): Promise<string>` on the `GitAPIService` class in `src/service/git/git-api-service.ts`. It resolves with the name of the fork repository owned by `sourceOwner`, including when that fork repository name differs from the upstream repository name, and it throws a `NotFoundError` when no fork is found.
- While performing the lookup, the method emits informational log messages describing its progress.
