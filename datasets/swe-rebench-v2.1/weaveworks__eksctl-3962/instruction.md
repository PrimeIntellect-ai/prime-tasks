`--version` flag for creating managed nodegroups with specific k8s version is not setting k8s version
## Managed nodegroup inherits cluster's k8s version despite `--version` being set
Creating a managed nodegroup with a k8s version that is different from the cluster k8s version is not really doing anything: the nodegroup inherits the version of the cluster.

Output of trying to create a managed ng with a k8s version that is different from that of the cluster:
```
eksctl create nodegroup --cluster test-2 --name test-ng-2 --managed --version 1.19
2021-06-04 12:32:59 [ℹ]  eksctl version 0.52.0
2021-06-04 12:32:59 [ℹ]  using region us-west-2
2021-06-04 12:33:00 [!]  will use version 1.19 for new nodegroup(s), while control plane version is 1.18; to automatically inherit the version use "--version=auto"
2021-06-04 12:33:09 [ℹ]  1 existing nodegroup(s) (test-ng) will be excluded
2021-06-04 12:33:09 [ℹ]  1 nodegroup (test-ng-2) was included (based on the include/exclude rules)
2021-06-04 12:33:09 [ℹ]  will create a CloudFormation stack for each of 1 managed nodegroups in cluster "test-2"
2021-06-04 12:33:09 [ℹ]  2 sequential tasks: { fix cluster compatibility, 1 task: { 1 task: { create managed nodegroup "test-ng-2" } } }
2021-06-04 12:33:09 [ℹ]  checking cluster stack for missing resources
2021-06-04 12:33:10 [ℹ]  cluster stack has all required resources
2021-06-04 12:33:10 [ℹ]  building managed nodegroup stack "eksctl-test-2-nodegroup-test-ng-2"
2021-06-04 12:33:10 [ℹ]  deploying stack "eksctl-test-2-nodegroup-test-ng-2"
2021-06-04 12:33:10 [ℹ]  waiting for CloudFormation stack "eksctl-test-2-nodegroup-test-ng-2"
2021-06-04 12:33:27 [ℹ]  waiting for CloudFormation stack "eksctl-test-2-nodegroup-test-ng-2"
2021-06-04 12:33:44 [ℹ]  waiting for CloudFormation stack "eksctl-test-2-nodegroup-test-ng-2"
2021-06-04 12:34:05 [ℹ]  waiting for CloudFormation stack "eksctl-test-2-nodegroup-test-ng-2"
2021-06-04 12:34:23 [ℹ]  waiting for CloudFormation stack "eksctl-test-2-nodegroup-test-ng-2"
2021-06-04 12:34:44 [ℹ]  waiting for CloudFormation stack "eksctl-test-2-nodegroup-test-ng-2"
2021-06-04 12:35:04 [ℹ]  waiting for CloudFormation stack "eksctl-test-2-nodegroup-test-ng-2"
2021-06-04 12:35:23 [ℹ]  waiting for CloudFormation stack "eksctl-test-2-nodegroup-test-ng-2"
2021-06-04 12:35:42 [ℹ]  waiting for CloudFormation stack "eksctl-test-2-nodegroup-test-ng-2"
2021-06-04 12:36:00 [ℹ]  waiting for CloudFormation stack "eksctl-test-2-nodegroup-test-ng-2"
2021-06-04 12:36:18 [ℹ]  waiting for CloudFormation stack "eksctl-test-2-nodegroup-test-ng-2"
2021-06-04 12:36:19 [ℹ]  no tasks
2021-06-04 12:36:19 [✔]  created 0 nodegroup(s) in cluster "test-2"
2021-06-04 12:36:20 [ℹ]  nodegroup "test-ng-2" has 2 node(s)
2021-06-04 12:36:20 [ℹ]  node "ip-192-168-52-123.us-west-2.compute.internal" is ready
2021-06-04 12:36:20 [ℹ]  node "ip-192-168-78-122.us-west-2.compute.internal" is ready
2021-06-04 12:36:20 [ℹ]  waiting for at least 2 node(s) to become ready in "test-ng-2"
2021-06-04 12:36:20 [ℹ]  nodegroup "test-ng-2" has 2 node(s)
2021-06-04 12:36:20 [ℹ]  node "ip-192-168-52-123.us-west-2.compute.internal" is ready
2021-06-04 12:36:20 [ℹ]  node "ip-192-168-78-122.us-west-2.compute.internal" is ready
2021-06-04 12:36:20 [✔]  created 1 managed nodegroup(s) in cluster "test-2"
2021-06-04 12:36:22 [ℹ]  checking security group configuration for all nodegroups
2021-06-04 12:36:22 [ℹ]  all nodegroups have up-to-date configuration
```

In the output above, there is a log that kind of acknowledges that the nodegroup being created has a different version to that of the cluster, but in the end the nodegroup still inherits the cluster's k8s version.

Another issue is that, currently, the k8s version of a nodegroup is not being returned when we do `get nodegroup`. This means that the only way to find the actual k8s version of a nodegroup is via the console (edit: #3810 adds capability for returning the nodegroup's k8s version!)

### Additional contract requirements

`--version` is not supported when creating a managed nodegroup: a managed
nodegroup's Kubernetes version is inherited from the control plane. Running
`eksctl create nodegroup --managed --version <version>` must fail with the error
message: `--version is only valid with unmanaged nodegroups`.
