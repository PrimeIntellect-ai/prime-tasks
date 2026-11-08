Replication group MultiAZ
I am launching an Elasticache (non cluster mode) with below composition.

```
 - name: ElastiCacheinstance
      base:
        apiVersion: cache.aws.crossplane.io/v1beta1
        kind: ReplicationGroup
        spec:
          forProvider:
            cacheSubnetGroupNameSelector:
              matchControllerRef: true
            securityGroupIDSelector:
              matchControllerRef: true
            applyModificationsImmediately: true
            atRestEncryptionEnabled: true
            numCacheClusters: 2
            automaticFailoverEnabled: true
          writeConnectionSecretToRef:
```

numCacheClusters value is 2 and automaticFailoverEnabled is enabled but MultiAZ is not enabled .
As per documentation it should be enabled when automaticFailoverEnabled is set to true.

I am able to enable Multi AZ by modifying it manually.

provider-aws: v0.20.0

### Additional contract requirements

- `ReplicationGroupParameters` (package `apis/cache/v1beta1`) exposes an optional
  `MultiAZEnabled *bool` field, serialized as `multiAZEnabled`. This field is how a
  user requests Multi-AZ for a replication group.
- `NewCreateReplicationGroupInput` and `NewModifyReplicationGroupInput` set the AWS
  `MultiAZEnabled` value from `ReplicationGroupParameters.MultiAZEnabled`.
- `ReplicationGroupNeedsUpdate` reports that an update is required when the desired
  `MultiAZEnabled` value differs from the observed AWS Multi-AZ status.
