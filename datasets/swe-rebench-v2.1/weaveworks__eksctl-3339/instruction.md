Internal nodegroup fields can be set and break nodegroup creation
A field `AdditionalEncryptedVolume` was added to the `NodeGroup` type not intended to be set by users. However, this field can still be set in ClusterConfig to any value and potentially break nodegroup creation because no validation is performed on it. Users should not be allowed to set this field.

An example ClusterConfig to reproduce this:

```yaml

apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: cluster
  region: us-west-2

nodeGroups:
- name: test
  AdditionalEncryptedVolume: "this-will-break-nodegroup-creation"

```

This will fail with:

```
You must use a valid fully-formed launch template. Invalid device name this-will-break-nodegroup-creation (Service: AmazonAutoScaling; Status Code: 400
```
