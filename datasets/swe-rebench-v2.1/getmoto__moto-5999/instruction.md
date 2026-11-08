Add ResourceGroupsTaggingAPI Support for Aurora clusters
Currently moto seems to not support rds:cluster and only supports rds:db . This issues is to ask to add support to fetch the rds aurora clusters using ResourceGroupsTaggingAPI

### Additional contract requirements

- The resources are retrieved through the `get_resources` method of the boto3 `resourcegroupstaggingapi` client.
- `get_resources` accepts a `ResourceTypeFilters` parameter (a list of resource-type identifiers) and a `TagFilters` parameter (a list of mappings, each with a `Key` and a `Values` list).
- The response contains a `ResourceTagMappingList` list. Each entry is a mapping with a `ResourceARN` string and a `Tags` list of `{"Key": ..., "Value": ...}` mappings describing the tags attached to that resource.
- Aurora clusters are addressed by the resource type `rds:cluster` and their snapshots by the resource type `rds:cluster-snapshot`.
