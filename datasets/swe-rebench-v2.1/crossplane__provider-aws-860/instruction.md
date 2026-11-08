ReplicationGroup: Add support for shards (node groups) scaling
### What problem are you facing?
It is impossible to change the number of node groups for a ReplicationGroup after deployment. Redis (cluster mode enabled) replication group does allow this, but Crossplane does not.

Probably related to https://github.com/crossplane/provider-aws/blob/master/pkg/clients/elasticache/elasticache.go#L193-L212 and https://github.com/crossplane/provider-aws/blob/f600ff88ad64df73295c96e4446be83b608ddfa4/apis/cache/v1beta1/replication_group_types.go#L424 (immutable)

### How could Crossplane help solve your problem?
This is probably a common use case which Crossplane should be able to handle.

### Additional contract requirements

- Add a public function `NewModifyReplicationGroupShardConfigurationInput(params v1beta1.ReplicationGroupParameters, id string, rg elasticachetypes.ReplicationGroup) *elasticache.ModifyReplicationGroupShardConfigurationInput` in package `pkg/clients/elasticache`. The returned request sets `ReplicationGroupId` to `id`, `NodeGroupCount` to the desired number of node groups, `ApplyImmediately` to the desired apply-immediately setting, and `NodeGroupsToRemove` to the oldest observed node groups that must be removed for a scale-down (no groups to remove when scaling up).
- Add a public function `ReplicationGroupShardConfigurationNeedsUpdate(kube v1beta1.ReplicationGroupParameters, rg elasticachetypes.ReplicationGroup) bool` in package `pkg/clients/elasticache`. It returns true when the desired number of node groups is set and differs from the number of observed node groups, and false otherwise.
- Add `ModifyReplicationGroupShardConfiguration(ctx context.Context, in *elasticache.ModifyReplicationGroupShardConfigurationInput, opts ...func(*elasticache.Options)) (*elasticache.ModifyReplicationGroupShardConfigurationOutput, error)` to the ElastiCache client interface in package `pkg/clients/elasticache`, and expose it on the fake client in package `pkg/clients/elasticache/fake` as a `MockModifyReplicationGroupShardConfiguration` field.

- A user must be able to change the desired node-group count on an already-deployed ReplicationGroup through the Kubernetes API.
