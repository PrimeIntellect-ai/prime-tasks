Implementation of FSx
Looking for [FSx Service](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/fsx.html) basic support including the following endpoints:

Implementation:

- create_file_system
- delete_file_system
- describe_file_systems
- tag_resource
- untag_resource

### Additional contract requirements

- `create_file_system` accepts `FileSystemType`, `StorageCapacity`, `StorageType`, `SubnetIds`, and `SecurityGroupIds`. It returns a `FileSystem` object containing `FileSystemId` and `FileSystemType`. Creating a file system returns its metadata, including a non-empty file-system ID and the requested file-system type.
- `describe_file_systems` accepts an optional `FileSystemIds` filter and returns a `FileSystems` list with entries containing `FileSystemId`, `FileSystemType`, `ResourceARN`, and `Tags`. Describing file systems returns the matching resources regardless of list order, and a requested ID filter limits results to those IDs.
- `delete_file_system` accepts `FileSystemId`. After a file system is deleted, it is no longer returned by subsequent describe requests.
- `tag_resource` accepts `ResourceARN` and `Tags`, a list of entries with `Key` and `Value` fields. Adding tags preserves the provided key/value pairs without requiring a particular ordering.
- `untag_resource` accepts `ResourceARN` and `TagKeys`. Removing tag keys removes those keys while retaining other tags.
