Cluster DNS calculation assumes that service cidr range is /16
**Is this a BUG REPORT or FEATURE REQUEST?**:
BUG REPORT
**What happened**:
Pods running on AL2 nodes started having DNS issues when running the latest version of instance manager. Upon investigation,
this appears to be because the EKS Cluster CIDR block is a /12 range - which causes this string replacement to fail https://github.com/keikoproj/instance-manager/blob/master/controllers/providers/aws/eks.go#L222.

**What you expected to happen**:
Pods should have working cluster DNS.
**How to reproduce it (as minimally and precisely as possible)**:
Have an EKS cluster with a ServiceCidr range that is not a /16 and run AL2 nodes.
**Anything else we need to know?**:

**Environment**:

- Kubernetes version:

```bash
kubectl version -o yaml
```

**Other debugging information (if applicable)**:

- InstanceGroup status:

```bash
kubectl describe instancegroup <ig-name>
```

- controller logs:

```bash
kubectl logs <instance-manager pod>
```
