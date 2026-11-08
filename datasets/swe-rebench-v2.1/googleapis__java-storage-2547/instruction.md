transfer manager PCUs should allowing specifying a key prefix for intermediate objects
In 2.37.0, PCU intermediate objects are written into the root of the bucket. The prefix used should be configurable. One use for setting a prefix is creating a lifecycle rule to clean up abandoned uploads.

### Additional contract requirements

`TransferManagerConfig.Builder` must let callers set a `PartNamingStrategy` for parallel composite upload intermediate objects through `setParallelCompositeUploadPartNamingStrategy(PartNamingStrategy)`. `PartNamingStrategy.prefix(String)` must cause all intermediate objects for those uploads to be created under the requested prefix.
