ssh-ed25519 keys wrongly assumed as unsupported
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
Create cluster with ssh-ed25519 key for ssh access.

**What happened?**
`Error: computing fingerprint for key "~/.ssh/some-ed25519-key.pub": error computing fingerprint for SSH public key: unexpected type of SSH key ("ssh.ed25519PublicKey"); AWS can only import RSA keys`

**How to reproduce it?**
Just try to create any cluster with ed25519 key.

**Anything else we need to know?**
AWS can import ed25519 from EC2 Console:
![image](https://user-images.githubusercontent.com/37580200/153652144-1c2109cb-7a86-40fc-b20d-a724e91c4024.png)


**Versions**
```
$ eksctl info
eksctl version: 0.82.0
kubectl version: v1.21.9
OS: windows
```

#### Summary
- So we need to investigate whether this error is coming from in eksctl
- we need to fix eksctl side so that users can use the ssh key type ssh-ed25519
