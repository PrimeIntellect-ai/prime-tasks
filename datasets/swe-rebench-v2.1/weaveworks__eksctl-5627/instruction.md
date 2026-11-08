[Bug] I should be able to create Windows and Ubuntu nodegroups with GPU instances (revert #4243)
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

### What were you trying to accomplish?
Create a Windows node group on an NVIDIA GPU instance

### What happened?
I receive an error from the code that prevents me from doing that in `eksctl`. The error appears in https://github.com/cPu1/eksctl/blob/4bcff91151570a1a15a2a0d8d07ae33799500380/pkg/apis/eksctl.io/v1alpha5/validation.go#L286

### How to reproduce it?
```yaml
...
nodeGroups:
  - name: xxx
    instanceType: g5.xlarge
    amiFamily: WindowsServer20H2CoreContainer
```
```sh
eksctl create cluster -f config.yaml
```
**Logs**
<!--
Include the output of the command line when running eksctl. If possible, eksctl should be run with debug logs. For example:
`eksctl get clusters -v 4`
Make sure you redact any sensitive information before posting.
If the output is long, please consider a Gist, or an html details tag.
-->
```
Error: couldn't create cluster provider from options: NVIDIA GPU instance types are not supported for WindowsServer20H2CoreContainer
```
**Anything else we need to know?**

I provision the nodes the rest of the way to GPU support.

**Versions**

```
$ eksctl info
eksctl version: 0.97.0
kubectl version: v1.22.5
OS: windows
```
