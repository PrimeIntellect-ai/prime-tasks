Ignoring rule container-resources makes every rule exceptional
**Which version of kube-score are you using?**

> kube-score version: v1.16.1

**What did you do?**

Added
```
annotations:
    kube-score/ignore: container-resources
```
And it made kube-score skip all the current issues

**What did you expect to see?**

> See only issues related to container-resources to skip

**What did you see instead?**

> kube-score passing all checks
