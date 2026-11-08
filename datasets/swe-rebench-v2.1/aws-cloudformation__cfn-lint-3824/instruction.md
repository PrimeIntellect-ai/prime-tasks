Linting Rule: Invalid EngineVersion on ElastiCache cluster
### Is this feature request related to a new rule or cfn-lint capabilities?

rules

### Describe the feature you'd like to request

I want the invalid redis version (i.e., the patch version is specified) to be added as a rule:

```yaml
  RedisCluster:
    Type: AWS::ElastiCache::CacheCluster
    # Deletion is the default policy.
    DeletionPolicy: Delete
    UpdateReplacePolicy: Delete
    Properties:
      Engine: redis
      CacheNodeType: cache.t4g.micro
      # RELATED TO ISSUE: Do not include patch versions in the EngineVersion (because it's invalid).
      EngineVersion: 7.1 # 7.1.0 is invalid.
      NumCacheNodes: 1
      ClusterName: "cluster-name"
      VpcSecurityGroupIds:
        - !Ref RedisSecurityGroup
      CacheSubnetGroupName: !Ref RedisSubnetGroup
```

### Describe the solution you'd like

The code snippet above should induce a linting error.

### Additional context

Just wasted 10 minutes on a deployment because of this.

### Is this something that you'd be interested in working on?

- [ ] 👋 I may be able to implement this feature request

### Would this feature include a breaking change?

- [ ] ⚠️ This feature might incur a breaking change

### Additional contract requirements

- The rule is identified by the ID `E3695`.
- The rule's `tags` are `["resources"]`.
- The rule's `source_url` is
  `https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/supported-engine-versions.html`.
- The rule's `description` is
  `Validate the Elasticache cluster engine along with the engine version`.
- The rule validates the `Engine` and `EngineVersion` properties of an
  `AWS::ElastiCache::CacheCluster` resource.
- The allowed `Engine` values are `memcached`, `redis`, and `valkey`.
- For `Engine: redis`, the allowed `EngineVersion` values are `4.0.10`,
  `5.0.6`, `6.0`, `6.2`, `7.0`, and `7.1`. A version that includes a
  patch component, such as `7.1.0`, is invalid and must produce a
  linting error.
- The linting error requested for the snippet above applies to the
  patch-version form of the version (for example `7.1.0`). The snippet's
  own `EngineVersion` value `7.1` is a valid version and does not itself
  produce a linting error; the snippet's comment notes that `7.1.0` is
  the invalid form.
- A violation is reported as a `ValidationError` whose `validator` is
  `enum` and whose `path` points at the offending property (`Engine` or
  `EngineVersion`).
