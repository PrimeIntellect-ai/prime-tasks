The filter 'kms-key-id' for DescribeSnapshots has not been implemented in Moto yet
Hello

Tried to create the following unit test :
create a volume
create a snapshot of the volume
copy the snapshot with a new KMS key
then call `describe_snapshots` with this filter `[{"Name": "kms-key-id", "Values": [kms_key]}]`

and got` moto.ec2.exceptions.FilterNotImplementedError: The filter 'kms-key-id' for DescribeSnapshots has not been implemented in Moto yet.`

### Additional contract requirements

- `DescribeSnapshots` supports the filter name `kms-key-id`; filtering with a KMS key value returns the snapshots associated with that key.
- Copying a snapshot with a KMS key (the `KmsKeyId` parameter of `CopySnapshot`) produces a snapshot that is encrypted.
