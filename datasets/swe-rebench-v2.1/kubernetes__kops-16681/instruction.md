Kops 1.29 with AWS CNI Networking not working in restricted AWS accounts
/kind bug

**1. What `kops` version are you running? The command `kops version`, will display
 this information.**

kops version
Client version: 1.29.0

**2. What Kubernetes version are you running? `kubectl version` will print the
 version if a cluster is running or provide the Kubernetes version specified as
 a `kops` flag.**

kubectl version
Client Version: v1.28.2
Kustomize Version: v5.0.4-0.20230601165947-6ce0bf390ce3
Server Version: v1.26.15

**3. What cloud provider are you using?**
AWS

**4. What commands did you run?  What is the simplest way to reproduce this issue?**
Upgrade a cluster running in an AWS account that is restricted to not use region `us-west-2`

**5. What happened after the commands executed?**
aws-node pods are unable to start because image `602401143452.dkr.ecr.us-west-2.amazonaws.com/amazon/aws-network-policy-agent:v1.0.7` cannot be pulled

**6. What did you expect to happen?**
kops update should be successful

The images for aws cni are configurable in the networkingSpec for AWS with the update to aws-cni (https://github.com/kubernetes/kops/pull/16297/files#diff-9b8cbd7c318a268f12b9ddc6312ff0661cdfbddec45db2a4dc738470f0fbd93d) a dependency to image 602401143452.dkr.ecr.us-west-2.amazonaws.com/amazon/aws-network-policy-agent was introduced without the option to customize the image.
This breaks the compatibility for clusters that has restricted image pull capabilities.
I would expect an option for customising the image like
```yaml
  networking:
    amazonvpc:
      imageName: 602401143452.dkr.ecr.eu-central-1.amazonaws.com/amazon-k8s-cni:v1.18.1
      initImageName: 602401143452.dkr.ecr.eu-central-1.amazonaws.com/amazon-k8s-cni-init:v1.18.1
      networkPolicyAgentImageName: 602401143452.dkr.ecr.eu-central-1.amazonaws.com/amazon/aws-network-policy-agent
```
As the networt policy feature of the AWS CNI is optional it might be a good option to disable it at all. In our case we are using cilium in chained mode with the AWS CNI for enforcing network policies and don't need the AWS CNI feature at all.

### Additional contract requirements

- The AWS networking spec field for configuring this image must be named `networkPolicyAgentImage`.
