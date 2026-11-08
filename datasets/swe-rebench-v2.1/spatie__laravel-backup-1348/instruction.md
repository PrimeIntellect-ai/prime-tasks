BackupDestination does not check write result
The class BackupDestination with function 'write' writes the backup file towards for example S3, but when f.e. S3MultipartUploadException occurs, the flysystem class returns 'false' instead of the exception. The backup is still marked as succesful.

### Additional contract requirements

- When the storage driver reports that writing a backup file failed, the failure must be surfaced to the caller of `BackupDestination::write()`, either as an exception or as a `false` result. A failed write must never be silently treated as a successful backup.
