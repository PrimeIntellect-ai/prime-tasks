Add latest AWS S3 storage class types
Can you please add the latest storage class types for S3:
'STANDARD','REDUCED_REDUNDANCY','STANDARD_IA','ONEZONE_IA','INTELLIGENT_TIERING','GLACIER','DEEP_ARCHIVE'
https://github.com/peak/s5cmd/blob/e1bf6cf824684f2d7f7c3f6296c265ac825a1c02/command/cp.go#L96

--storage-class (string) The type of storage to use for the object. Valid choices are: STANDARD | REDUCED_REDUNDANCY | STANDARD_IA | ONEZONE_IA | INTELLIGENT_TIERING | GLACIER | DEEP_ARCHIVE. Defaults to 'STANDARD'
https://docs.aws.amazon.com/cli/latest/reference/s3/cp.html

Maybe it is also an idea to add the latest google cloud storage classes (standard, nearline, coldline):
https://cloud.google.com/storage/docs/storage-classes
