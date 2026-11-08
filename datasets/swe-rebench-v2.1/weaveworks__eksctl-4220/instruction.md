eksctl enable flux command results in a "invalid memory address or nil pointer dereference"
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
<!-- Information about the command you ran and what you expected to happen. -->
I was trying to install flux.

**What happened?**
<!-- A description of actual behavior (with error messages). -->
Running the `eksctl enable flux -v 4 --config-file configs/configs.yaml` resulted in a panic.
**How to reproduce it?**
<!--
Include ALL the steps to reproduce the bug.
```
eksctl enable flux -v 4 --config-file configs/configs.yaml
```

If using a config file, include it here, removing any sensitive information!
-->
```
apiVersion: eksctl.io/v1alpha5
availabilityZones:
- us-east-2c
- us-east-2b
- us-east-2a
cloudWatch:
  clusterLogging: {}
iam:
  vpcResourceControllerPolicy: true
  withOIDC: false
kind: ClusterConfig
managedNodeGroups:
- amiFamily: AmazonLinux2
  desiredCapacity: 1
  disableIMDSv1: false
  disablePodIMDS: false
  iam:
    withAddonPolicies:
      albIngress: false
      appMesh: false
      appMeshPreview: false
      autoScaler: false
      certManager: false
      cloudWatch: false
      ebs: false
      efs: false
      externalDNS: false
      fsx: false
      imageBuilder: false
      xRay: false
  instanceSelector: {}
  instanceTypes:
  - t2.medium
  labels:
    alpha.eksctl.io/cluster-name: steve-fraser-test-cluster
    alpha.eksctl.io/nodegroup-name: ng-new
  maxSize: 1
  minSize: 1
  name: ng-new
  privateNetworking: false
  releaseVersion: ""
  securityGroups:
    withLocal: null
    withShared: null
  ssh:
    allow: true
    publicKeyPath: ~/.ssh/id_rsa.pub
  tags:
    alpha.eksctl.io/nodegroup-name: ng
    alpha.eksctl.io/nodegroup-type: managed
  volumeIOPS: 3000
  volumeSize: 80
  volumeThroughput: 125
  volumeType: gp3
metadata:
  name: steve-fraser-test-cluster
  region: us-east-2
  version: "1.19"
privateCluster:
  enabled: false
vpc:
  autoAllocateIPv6: false
  cidr: 192.168.0.0/16
  clusterEndpoints:
    privateAccess: false
    publicAccess: true
  manageSharedNodeSecurityGroupRules: true
  nat:
    gateway: Single
```

**Logs**
<!--
Include the output of the command line when running eksctl. If possible, eksctl should be run with debug logs. For example:
`eksctl get clusters -v 4`
Make sure you redact any sensitive information before posting.
If the output is long, please consider a Gist, or an html details tag.
-->

```
eksctl enable flux -v 4 --config-file configs/configs.yaml

panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x0 pc=0x2a49872]

goroutine 1 [running]:
github.com/weaveworks/eksctl/pkg/ctl/cmdutils.NewGitOpsConfigLoader.func1()
        github.com/weaveworks/eksctl/pkg/ctl/cmdutils/gitops.go:315 +0x52
github.com/weaveworks/eksctl/pkg/ctl/cmdutils.(*GitOpsConfigLoader).Load(0xc000398b90)
        github.com/weaveworks/eksctl/pkg/ctl/cmdutils/gitops.go:361 +0xce
github.com/weaveworks/eksctl/pkg/ctl/enable.configureAndRun.func2(0xc0006bcf00, {0xc00069d000, 0x4, 0x4})
        github.com/weaveworks/eksctl/pkg/ctl/enable/flux.go:40 +0xd1
github.com/spf13/cobra.(*Command).execute(0xc0006bcf00, {0xc00069cfc0, 0x4, 0x4})
        github.com/spf13/cobra@v1.2.1/command.go:856 +0x60e
github.com/spf13/cobra.(*Command).ExecuteC(0xc000139180)
        github.com/spf13/cobra@v1.2.1/command.go:974 +0x3bc
github.com/spf13/cobra.(*Command).Execute(...)
        github.com/spf13/cobra@v1.2.1/command.go:902
main.main()
        github.com/weaveworks/eksctl/cmd/eksctl/main.go:95 +0x525```

**Anything else we need to know?**
<!--
What OS are you using?
Are you using a downloaded binary or did you compile eksctl?
What type of AWS credentials are you using (i.e. default/named profile, MFA)? - please don't include actual credentials though!
-->

**Versions**
<!--
Please paste in the output of this command:
-->
```
$ eksctl info
```

eksctl info
eksctl version: 0.66.0
kubectl version: v1.22.1
OS: darwin

flux  --version
flux version 0.17.1

### Additional contract requirements

- When `gitops` or `gitops.flux` is not configured, `eksctl enable flux` must return the error `gitops.flux must be set`.
