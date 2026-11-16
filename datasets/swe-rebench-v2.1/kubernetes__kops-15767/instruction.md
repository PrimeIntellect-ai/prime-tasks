Failed to set env var when using kubetest2
/kind bug

**1. What `kops` version are you running? The command `kops version`, will display
 this information.**
Client version: 1.26.3 (git-v1.26.3)

**2. What Kubernetes version are you running? `kubectl version` will print the
 version if a cluster is running or provide the Kubernetes version specified as
 a `kops` flag.**
1.27

**3. What cloud provider are you using?**
aws

**4. What commands did you run?  What is the simplest way to reproduce this issue?**
```
kubetest2 kops -v=2 --cloud-provider=aws --cluster-name=scalability1.k8s.local --kops-binary-path=/Users/pgogia/workspace/golang/src/k8s.io/bin/kops --admin-access=0.0.0.0/0 --env=KOPS_FEATURE_FLAGS=ClusterAddons, --validation-wait=30m --up --kubernetes-version=v1.27.4 '--create-args=--networking=amazonvpc --set cluster.spec.networking.amazonVPC.env=ENABLE_PREFIX_DELEGATION=true --image=ssm:/aws/service/canonical/ubuntu/server/20.04/stable/current/arm64/hvm/ebs-gp2/ami-id --set spec.kubeScheduler.authorizationAlwaysAllowPaths=/healthz --set spec.kubeScheduler.authorizationAlwaysAllowPaths=/metrics --node-count=500 --node-size=c6g.medium --control-plane-count=3 --master-size=c6g.16xlarge'
```
**5. What happened after the commands executed?**
Fails with this error
```
Error: cannot set field "spec.networking.amazonVPC.env": unhandled type "kops.EnvVar"
Error: exit status 1
```
**6. What did you expect to happen?**
Cluster creation to succeed

**7. Please provide your cluster manifest. Execute
  `kops get --name my.example.com -o yaml` to display your cluster manifest.
  You may want to remove your cluster name and other sensitive information.**

```yaml
```

**8. Please run the commands with most verbose logging by adding the `-v 10` flag.
  Paste the logs into this report, or in a gist and provide the gist link here.**

**9. Anything else do we need to know?**
I am trying to set the env var for amazon vpc cni like this `--set cluster.spec.networking.amazonVPC.env=ENABLE_PREFIX_DELEGATION=true` but seems like the type `"kops.EnvVar"` is not handled [here](https://github.com/kubernetes/kops/blob/master/util/pkg/reflectutils/access.go#L197) in `setType` function.
