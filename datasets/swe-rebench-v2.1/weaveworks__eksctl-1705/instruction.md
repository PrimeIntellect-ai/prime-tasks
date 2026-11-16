managedNodeGroups fails with imageBuilder
### DESCRIPTION

When you create a new cluster with `managedNodeGroups` and set the `iam.withAddonPolicies.imageBuilder` to `true`, the `Nodegroup/ManagedNodeGroup` will fail, causing a ROLLBACK.

### STEPS

```bash
eksctl create cluster -f cluster.yaml
```

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: test3-cluster
  region: us-east-2

managedNodeGroups:
  - name: test3-workers
    minSize: 2
    maxSize: 4
    desiredCapacity: 3
    labels: {role: worker}
    tags:
      nodegroup-role: worker
    iam:
      withAddonPolicies:
        externalDNS: true
        certManager: true
        imageBuilder: true
```

### EXPECTED
This not to fail.

### ACTUAL

```
[ℹ]  eksctl version 0.11.1
[ℹ]  using region us-east-2
[ℹ]  setting availability zones to [us-east-2c us-east-2a us-east-2b]
[ℹ]  subnets for us-east-2c - public:192.168.0.0/19 private:192.168.96.0/19
[ℹ]  subnets for us-east-2a - public:192.168.32.0/19 private:192.168.128.0/19
[ℹ]  subnets for us-east-2b - public:192.168.64.0/19 private:192.168.160.0/19
[ℹ]  using Kubernetes version 1.14
[ℹ]  creating EKS cluster "test3-cluster" in "us-east-2" region with managed nodes
[ℹ]  1 nodegroup (test3-workers) was included (based on the include/exclude rules)
[ℹ]  will create a CloudFormation stack for cluster itself and 0 nodegroup stack(s)
[ℹ]  will create a CloudFormation stack for cluster itself and 1 managed nodegroup stack(s)
[ℹ]  if you encounter any issues, check CloudFormation console or try 'eksctl utils describe-stacks --region=us-east-2 --cluster=test3-cluster'
[ℹ]  CloudWatch logging will not be enabled for cluster "test3-cluster" in "us-east-2"
[ℹ]  you can enable it with 'eksctl utils update-cluster-logging --region=us-east-2 --cluster=test3-cluster'
[ℹ]  Kubernetes API endpoint access will use default of {publicAccess=true, privateAccess=false} for cluster "test3-cluster" in "us-east-2"
[ℹ]  2 sequential tasks: { create cluster control plane "test3-cluster", create managed nodegroup "test3-workers" }
[ℹ]  building cluster stack "eksctl-test3-cluster-cluster"
[ℹ]  deploying stack "eksctl-test3-cluster-cluster"
[ℹ]  building managed nodegroup stack "eksctl-test3-cluster-nodegroup-test3-workers"
[ℹ]  deploying stack "eksctl-test3-cluster-nodegroup-test3-workers"
[✖]  unexpected status "ROLLBACK_IN_PROGRESS" while waiting for CloudFormation stack "eksctl-test3-cluster-nodegroup-test3-workers"
[ℹ]  fetching stack events in attempt to troubleshoot the root cause of the failure
[✖]  AWS::IAM::Policy/PolicyCertManagerGetChange: CREATE_FAILED – "Resource creation cancelled"
[✖]  AWS::IAM::Policy/PolicyCertManagerHostedZones: CREATE_FAILED – "Resource creation cancelled"
[✖]  AWS::IAM::Policy/PolicyCertManagerChangeSet: CREATE_FAILED – "Resource creation cancelled"
[✖]  AWS::EKS::Nodegroup/ManagedNodeGroup: CREATE_FAILED – "The provided role doesn't have the Amazon EKS Managed Policies associated with it. Please ensure the following policies [arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy, arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy, arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly] are attached (Service: AmazonEKS; Status Code: 400; Error Code: InvalidParameterException; Request ID: ccf7fea0-2d47-4a61-8930-b0a7b1a9d433)"
[ℹ]  1 error(s) occurred and cluster hasn't been created properly, you may wish to check CloudFormation console
[ℹ]  to cleanup resources, run 'eksctl delete cluster --region=us-east-2 --name=test3-cluster'
[✖]  waiting for CloudFormation stack "eksctl-test3-cluster-nodegroup-test3-workers": ResourceNotReady: failed waiting for successful resource state
[✖]  failed to create cluster "test3-cluster"
```

### VERSIONS

* Mac OS X `10.14.6`
* eksctl `0.11.1`
* kubectl `v1.17.0`

### NOTES

The same cluster definition without the `imageBuilder: true` will succeed.
