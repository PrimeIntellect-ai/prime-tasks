Allow IOPS config option for io1 volumeType
**Is this a BUG REPORT or FEATURE REQUEST?**:
FEATURE
**What happened**:
Allow IOPS config option for io1 volumeType

https://github.com/keikoproj/instance-manager/blob/5843c10e7b365f7206542e08efd754413d51799c/api/v1alpha1/instancegroup_types.go#L193-L196

More Details about io1
https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-volume-types.html


**What you expected to happen**:

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

### Additional contract requirements

- Volume configuration must accept the JSON property `iops`; for an `io1` volume, its configured value must be applied as the volume’s provisioned IOPS.
