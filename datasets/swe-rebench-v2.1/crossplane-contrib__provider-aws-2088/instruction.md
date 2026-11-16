ReplicationGroup engineVersion check invalid - 0.49.1
### What happened?
This PR https://github.com/crossplane-contrib/provider-aws/pull/1985 i believe results in a bug where existing redis clusters with `engineVersion: 6.x` set are failing to sync due to the check for version trying to cast x to an int in 6.x despite it being a completely valid option. Curiously creating a new replicationgroup with `6.x` doesn't have any issues as of yet

### How can we reproduce it?
1) Have an existing replicationgroup as so (obviously switch out the bits required for your test env)
```
apiVersion: cache.aws.crossplane.io/v1beta1
kind: ReplicationGroup
metadata:
  name: test-redis
spec:
  deletionPolicy: Delete
  forProvider:
    applyModificationsImmediately: true
    atRestEncryptionEnabled: true
    authEnabled: true
    automaticFailoverEnabled: true
    cacheNodeType: cache.t3.micro
    cacheParameterGroupName: default.redis6.x
    cacheSubnetGroupName: lab-data
    engine: redis
    engineVersion: 6.x
    multiAZEnabled: false
    numCacheClusters: 2
    preferredMaintenanceWindow: wed:22:00-wed:23:00
    region: eu-west-1
    replicationGroupDescription: test
    securityGroupIdRefs:
      - name: lab-elasticache-sg
    securityGroupIds:
      - sg-0f0506ae5e242fa6fe
    snapshotRetentionLimit: 0
    snapshotWindow: 01:00-02:00
    transitEncryptionEnabled: true
  managementPolicies:
    - '*'
  providerConfigRef:
    name: aws
  writeConnectionSecretToRef:
    name: test
    namespace: flux-system
```

2) Upgrade to 0.49.1 (in theory anything after 0.47.0 probably has this issue)

3) Observe existing elasticache resource has error as so
```
    - lastTransitionTime: '2024-08-21T09:15:00Z'
      message: >-
        update failed: unable to parse version number: unable to parse version
        number: strconv.Atoi: parsing "x": invalid syntax
      reason: ReconcileError
      status: 'False'
      type: Synced
```

### What environment did it happen in?
Crossplane version: 1.16.0
Provider version: 0.49.1
K8s Distro: EKS
K8s Version: 1.30
