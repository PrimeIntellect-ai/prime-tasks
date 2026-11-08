Trying to create Windows nodegroup with 1.15 causes SIGSEGV
**What happened?**
A description of actual behavior (with error messages).

I am trying to create a Windows nodegroup. I followed the instructions on the official documentation: https://docs.aws.amazon.com/eks/latest/userguide/launch-windows-workers.html

I ran this command:

$ eksctl create nodegroup --cluster training --profile mfa --region us-east-1 --name windows -m 1 -M 3 -N 2 --node-ami-family WindowsServer2019FullContainer --node-type m5.large

And got this error:

[ℹ]  eksctl version 0.15.0
[ℹ]  using region us-east-1
[ℹ]  1 nodegroup(s) that already exist (ng-b392aa65) will be excluded
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x8 pc=0x1844eb0]

goroutine 1 [running]:
github.com/weaveworks/eksctl/pkg/ami.Use(0x33eabc0, 0xc00000ea88, 0xc0003242c0, 0x7ffc460ed7bc, 0x4)
	github.com/weaveworks/eksctl@/pkg/ami/api.go:57 +0x160
github.com/weaveworks/eksctl/pkg/eks.EnsureAMI(0x33ad7e0, 0xc0004d7220, 0x7ffc460ed7bc, 0x4, 0xc0003242c0, 0x0, 0x0)
	github.com/weaveworks/eksctl@/pkg/eks/api.go:301 +0x361
github.com/weaveworks/eksctl/pkg/ctl/create.doCreateNodeGroups(0xc00029e280, 0xc0003242c0, 0x1, 0x0, 0x0)
	github.com/weaveworks/eksctl@/pkg/ctl/create/nodegroup.go:127 +0x3db
github.com/weaveworks/eksctl/pkg/ctl/create.createNodeGroupCmd.func1(0xc00030ca00, 0xc00025a3c0, 0x0, 0x14, 0x0, 0x0)
	github.com/weaveworks/eksctl@/pkg/ctl/create/nodegroup.go:40 +0xa5
github.com/spf13/cobra.(*Command).execute(0xc00030ca00, 0xc00025a280, 0x14, 0x14, 0xc00030ca00, 0xc00025a280)
	github.com/spf13/cobra@v0.0.5/command.go:826 +0x460
github.com/spf13/cobra.(*Command).ExecuteC(0xc00030c280, 0xc0002b1c20, 0x1, 0x1)
	github.com/spf13/cobra@v0.0.5/command.go:914 +0x2fb
github.com/spf13/cobra.(*Command).Execute(...)
	github.com/spf13/cobra@v0.0.5/command.go:864
main.main()
	github.com/weaveworks/eksctl@/cmd/eksctl/main.go:79 +0x407

When I added --version 1.14, everything created successfully, but using 1.15 does not work at all.

To reproduce, all I did was run the "install-vpc-controllers" command from the documentation above and then the command. The cluster itself was default.

**Anything else we need to know?**
What OS are you using, are you using a downloaded binary or did you compile eksctl, what type of AWS credentials are you using (i.e. default/named profile, MFA) - please don't include actual credentials though!

I'm on Ubuntu 18.04.4 with eksctl 0.15.0

**Versions**
Please paste in the output of these commands:
```
$ eksctl version
$ kubectl version
```lrelease

**Logs**
Include the output of the command line when running eksctl. If possible, eksctl should be run with debug logs. For example:
`eksctl get clusters -v 4`
Make sure you redact any sensitive information before posting.
If the output is long, please consider a Gist.
