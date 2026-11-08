kops 1.29.0 can't deploy aws-iam-authenticator pods - image tag not found in registry
/kind bug

**1. What `kops` version are you running? The command `kops version`, will display
 this information.**
kops 1.29.0

**2. What Kubernetes version are you running? `kubectl version` will print the
 version if a cluster is running or provide the Kubernetes version specified as
 a `kops` flag.**
v1.29.5

**3. What cloud provider are you using?**
AWS

**4. What commands did you run?  What is the simplest way to reproduce this issue?**
Enabled in cluster spec
```
  authentication:
    aws: {}
```

**5. What happened after the commands executed?**
aws-iam-authenticator pods can't pull their specified image because it's missing in the registry

```
  Warning  Failed       3m8s (x3 over 3m53s)   kubelet            Failed to pull image "602401143452.dkr.ecr.us-west-2.amazonaws.com/amazon/aws-iam-authenticator:v0.5.27": rpc error: code = NotFound desc = failed to pull and unpack image "602401143452.dkr.ecr.us-west-2.amazonaws.com/amazon/aws-iam-authenticator:v0.5.27": failed to resolve reference "602401143452.dkr.ecr.us-west-2.amazonaws.com/amazon/aws-iam-authenticator:v0.5.27": 602401143452.dkr.ecr.us-west-2.amazonaws.com/amazon/aws-iam-authenticator:v0.5.27: not found
  Warning  Failed       3m8s (x3 over 3m53s)   kubelet            Error: ErrImagePull
  Normal   BackOff      2m41s (x4 over 3m52s)  kubelet            Back-off pulling image "602401143452.dkr.ecr.us-west-2.amazonaws.com/amazon/aws-iam-authenticator:v0.5.27"
  Warning  Failed       2m41s (x4 over 3m52s)  kubelet            Error: ImagePullBackOff
```


**6. What did you expect to happen?**
aws-iam-authenticator pods running

**7. Please provide your cluster manifest. Execute
  `kops get --name my.example.com -o yaml` to display your cluster manifest.
  You may want to remove your cluster name and other sensitive information.**

```yaml

apiVersion: kops.k8s.io/v1alpha2
kind: Cluster
metadata:
  creationTimestamp: "2024-06-05T12:22:06Z"
  generation: 3
  name: XXXXXXXXXXXXXXXXXX
spec:
  additionalPolicies:
    master: |
      [
        {
          "Effect": "Allow",
          "Action": ["ecr:BatchImportUpstreamImage","ecr:CreateRepository","ecr:TagResource"],
          "Resource": ["*"]
        }
      ]
    node: |
      [
        {
          "Effect": "Allow",
          "Action": ["ecr:BatchImportUpstreamImage","ecr:CreateRepository","ecr:TagResource"],
          "Resource": ["*"]
        }
      ]
  api:
    dns: {}
  authentication:
    aws: {}
  authorization:
    rbac: {}
  certManager:
    enabled: true
    managed: false
  channel: stable
  cloudLabels:
    Environment: development
  cloudProvider: aws
  configBase: s3://XXXXXXXXXXXXXXXXXXXX/kops/XXXXXXXXXXXXXXXXXXX
  dnsZone: XXXXXXXXXXXXXXXXXXXX
  etcdClusters:
  - cpuRequest: 200m
    etcdMembers:
    - encryptedVolume: true
      instanceGroup: control-plane-us-east-2a
      name: a
    - encryptedVolume: true
      instanceGroup: control-plane-us-east-2b
      name: b
    - encryptedVolume: true
      instanceGroup: control-plane-us-east-2c
      name: c
    manager:
      backupRetentionDays: 90
    memoryRequest: 100Mi
    name: main
  - cpuRequest: 100m
    etcdMembers:
    - encryptedVolume: true
      instanceGroup: control-plane-us-east-2a
      name: a
    - encryptedVolume: true
      instanceGroup: control-plane-us-east-2b
      name: b
    - encryptedVolume: true
      instanceGroup: control-plane-us-east-2c
      name: c
    manager:
      backupRetentionDays: 90
    memoryRequest: 100Mi
    name: events
  iam:
    allowContainerRegistry: true
    legacy: false
    useServiceAccountExternalPermissions: true
  kubeDNS:
    nodeLocalDNS:
      enabled: true
    provider: CoreDNS
  kubeProxy:
    enabled: false
  kubelet:
    anonymousAuth: false
  kubernetesApiAccess:
  - 0.0.0.0/0
  - ::/0
  kubernetesVersion: 1.29.5
  masterPublicName: api.XXXXXXX
  metricsServer:
    enabled: true
    insecure: false
  networkCIDR: 10.105.0.0/16
  networkID: vpc-05323df512cb1db11
  networking:
    cilium:
      enableNodePort: true
      hubble:
        enabled: true
  nonMasqueradeCIDR: 100.64.0.0/10
  podIdentityWebhook:
    enabled: true
  serviceAccountIssuerDiscovery:
    discoveryStore: s3://XXXXXXXXXXXXXXXXXXX/XXXXXXXXXXXXXXXX
    enableAWSOIDCProvider: true
  sshAccess:
  - 0.0.0.0/0
  - ::/0
  subnets:
  - cidr: 10.105.64.0/19
    ipv6CIDR: /64#40
    name: us-east-2a
    type: Public
    zone: us-east-2a
  - cidr: 10.105.96.0/19
    ipv6CIDR: /64#41
    name: us-east-2b
    type: Public
    zone: us-east-2b
  - cidr: 10.105.128.0/19
    ipv6CIDR: /64#42
    name: us-east-2c
    type: Public
    zone: us-east-2c
  sysctlParameters:
  - net.ipv4.neigh.default.gc_thresh2=28672
  - net.ipv4.neigh.default.gc_thresh3=32768
  topology:
    dns:
      type: Public

```

**8. Please run the commands with most verbose logging by adding the `-v 10` flag.
  Paste the logs into this report, or in a gist and provide the gist link here.**

**9. Anything else do we need to know?**

### Additional contract requirements

- When AWS authentication is enabled and no custom image is specified, the aws-iam-authenticator container image must be `public.ecr.aws/eks-distro/kubernetes-sigs/aws-iam-authenticator:v0.6.20-eks-1-30-7`.
