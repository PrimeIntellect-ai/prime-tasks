Print each project branch head commit in checkout summary
Currently the checkout summary shows information about each project that was checkout, like

```
# Checkout summary
[INFO] [kiegroup/drools]
[INFO] 	 Project taken from kiegroup/drools:main-integration-quarkus-lts
[INFO] [kiegroup/kogito-runtimes]
[INFO] 	 Project taken from kiegroup/kogito-runtimes:main-integration-quarkus-lts
[INFO] [kiegroup/kogito-apps]
[INFO] 	 Project taken from kiegroup/kogito-apps:main-integration-quarkus-lts
[INFO] [kiegroup/kogito-examples]
[INFO] 	 Project taken from kiegroup/kogito-examples:main-integration-quarkus-lts
[INFO] [kiegroup/kogito-images]
[INFO] 	 Project taken from kiegroup/kogito-images:main-integration-quarkus-lts
```

We could also include the branch head commit hash in the summary, which I think would help specially with the nightlies as many changes are merged daily and we are currently not sure from what commit each project of the nightly was built (specially if the builds fail)

### Additional contract requirements

- The checkout summary must print, for every project that was checked out, the branch head commit hash returned by `GitCLIService.head` for that project. The summary line for a checked out project must have the format:

  `\t Project taken from <targetGroup>/<targetName>:<targetBranch> (Branch HEAD <branchHead>)`

  where `<branchHead>` is the value returned by `GitCLIService.head` for the project's checkout directory.
