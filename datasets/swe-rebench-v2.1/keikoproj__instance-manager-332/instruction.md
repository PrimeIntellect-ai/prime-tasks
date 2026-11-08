SubFamilyFlexible calculations should ensure that instance types have the same supported architectures.
**Is this a BUG REPORT or FEATURE REQUEST?**:
BUG REPORT
**What happened**:
I configured an InstanceGroup to use spot instances with the SubFamilyFlexible option, with the main instance type being set to m6i.2xlarge. Instance Manager also included m6g.2xlarges in the ASG, which have a different supported architecture (arm64) then the main instance type (amd64)
**What you expected to happen**:
Only instances with the same architecture should be used.
**How to reproduce it (as minimally and precisely as possible)**:

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
