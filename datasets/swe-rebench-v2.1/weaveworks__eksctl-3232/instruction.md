eksctl create not accepting vpc non-default cidr
**What happened?**
 eksctl -v4 create cluster -f eksctl/eks-course.yaml
2020-10-12T17:16:39Z [ℹ]  eksctl version 0.29.2
2020-10-12T17:16:39Z [ℹ]  using region us-east-1
Error: VPC CIDR block "10.205.117.0/24" is not the same as "10.205.251.0/25"

**What you expected to happen?**
A new eks cluster would be created using the non-default vpc cidr

**How to reproduce it?**
create a vpc with a default cidr plus one additional one.  use the non-default on to specify the vpc cidr, including subnets under the none default cidr

**Anything else we need to know?**
```
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: EKS-course-cluster
  region: us-east-1

vpc:
  id: "vpc-123"
  cidr: "<put in non-default cidr in vpc here>"
  subnets:
    private:
      subnet-us-east-1b:
        id: "subnet-123"
        cidr: "<put in non-default vpc subnet cidr here>"
      subnet-us-east-1a:
        id: "subnet-124"
        cidr: "<put in non-default vpc subnet cidr here>"

nodeGroups:
  - name: ng-1
    instanceType: t2.small
    desiredCapacity: 2
    volumeSize: 20
    ssh: # use existing EC2 key
      publicKeyName: 'yourkey'
    privateNetworking: true
```

**Versions**
Please paste in the output of these commands:
```
eksctl version
0.29.2

kubectl version
Client Version: version.Info{Major:"1", Minor:"19", GitVersion:"v1.19.2", GitCommit:"f5743093fd1c663cb0cbc89748f730662345d44d", GitTreeState:"clean", BuildDate:"2020-09-16T13:41:02Z", GoVersion:"go1.15", Compiler:"gc", Platform:"linux/amd64"}

```

**Logs**
```
eksctl -v4 create cluster -f eksctl/eks-course.yaml
2020-10-12T17:24:13Z [ℹ]  eksctl version 0.29.2
2020-10-12T17:24:13Z [ℹ]  using region us-east-1
2020-10-12T17:24:13Z [▶]  role ARN for the current session is "redacted"
Error: VPC CIDR block "redacted" is not the same as "redacted"

### Additional contract requirements

- When the configured VPC CIDR is `10.2.0.0/16` and that CIDR is not attached to the VPC, return the exact error `VPC CIDR block "10.2.0.0/16" not found in VPC`.
