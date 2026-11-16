Cannot fetch nodegroups
<!--
Thank you for opening this bug report! You are helping make eksctl a better project :)
In order to help us process this issue faster, please provide as much detail as possible.

When providing command examples, error output or code samples, please use code blocks.
For verbose output, for example logs, please either create a gist or use html details tags.
-->

<!--
Before you start writing:
1. Please search through existing issues to see whether your problem has already been reported.
2. Download the latest version of eksctl to see whether the problem has already been fixed.

For more information on how to open a bug report in eksctl, please refer to our issue submission guide.
https://github.com/weaveworks/eksctl/blob/main/CONTRIBUTING.md#opening-issues
-->

**What were you trying to accomplish?**
I was trying to get the NodeInstanceRoleARN to set up IAM roles. I had just create this cluster.

**What happened?**
<!-- A description of actual behavior (with error messages). -->
```
❯ eksctl get nodegroup --cluster ${CLUSTER_NAME} -n workers-lg
2021-06-23 18:24:16 [ℹ]  eksctl version 0.54.0
2021-06-23 18:24:16 [ℹ]  using region us-east-1
Error: getting nodegroup's kubernetes version: failed to list nodes: no nodes were found
```

**How to reproduce it?**
<!--
Include ALL the steps to reproduce the bug.

If using a config file, include it here, removing any sensitive information!
-->
1. Create a cluster with unmanaged node groups, defined in a ClusterConfig
2. Use `eksctl create cluster -f cluster.yaml` to do so
3. Run `eksctl get nodegroup --cluster ${CLUSTER_NAME}` to fetch nodegroup info

I think this part of the config should be enough: https://gist.github.com/283b3decf7e1dc88e09c89d876d05aad

**Logs**
<!--
Include the output of the command line when running eksctl. If possible, eksctl should be run with debug logs. For example:
`eksctl get clusters -v 4`
Make sure you redact any sensitive information before posting.
If the output is long, please consider a Gist, or an html details tag.
-->
https://gist.github.com/d9a9c32e80df6dcb7df7c0d787631c22

**Anything else we need to know?**
<!--
What OS are you using?
Are you using a downloaded binary or did you compile eksctl?
What type of AWS credentials are you using (i.e. default/named profile, MFA)? - please don't include actual credentials though!
-->
macOS, installed eksctl 0.54.0 from brew

**Versions**
<!--
Please paste in the output of these commands:
-->
```
❯ eksctl version
0.54.0
❯ kubectl version
Client Version: version.Info{Major:"1", Minor:"21", GitVersion:"v1.21.1", GitCommit:"5e58841cce77d4bc13713ad2b91fa0d961e69192", GitTreeState:"clean", BuildDate:"2021-05-12T14:18:45Z", GoVersion:"go1.16.4", Compiler:"gc", Platform:"darwin/amd64"}
Server Version: version.Info{Major:"1", Minor:"16+", GitVersion:"v1.16.15-eks-cf75c9", GitCommit:"cf75c9601ec63a63ba54c1c47caa9945af1f3a81", GitTreeState:"clean", BuildDate:"2021-02-13T00:14:16Z", GoVersion:"go1.13.15", Compiler:"gc", Platform:"linux/amd64"}
WARNING: version difference between client (1.21) and server (1.16) exceeds the supported minor version skew of +/-1
```

### Additional contract requirements

- For an unmanaged node group whose desired capacity is zero, `eksctl get nodegroup` must return its summary, including `NodeInstanceRoleARN`, without failing merely because no Kubernetes nodes are available to determine a version.
