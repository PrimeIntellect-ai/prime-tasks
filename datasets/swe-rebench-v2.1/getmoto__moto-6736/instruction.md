Aurora Postgres Does Not Support Mock ServerlessV2
From what I can tell, Aurora Postgres does not support ServerlessV2ScalingConfiguration like Neptune does. Support for this would be great!

### Additional contract requirements

- `CreateDBCluster` should accept the optional `ServerlessV2ScalingConfiguration` with `MinCapacity` and/or `MaxCapacity`, and include the supplied configuration in the returned cluster. A subsequent `DescribeDBClusters` response should include that configuration as well.
