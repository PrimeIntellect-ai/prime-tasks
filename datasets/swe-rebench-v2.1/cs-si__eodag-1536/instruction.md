Geodes & Geodes_s3 have the same key in pre release 3.1.0b2
**Describe the bug**

- The latest pre-release adds geodes_s3 for internal access the CNES data lake
- The latest provider config uses the same key
```
- geodes:
    priority: # Lower value means lower priority (Default: 0)
    search: # Search parameters configuration
    auth:
        credentials:
            apikey:
    download:
        extract:
        output_dir:
geodes:
    priority: # Lower value means lower priority (Default: 0)
    search: # Search parameters configuration
    auth:
        credentials:
            aws_access_key_id:
            aws_secret_access_key:
            aws_session_token:
    download:
        extract:
        output_dir:
```
- This breaks the public Geodes access with error: `MisconfiguredError('The following credentials are missing for provider geodes: aws_access_key_id, aws_secret_access_key, aws_session_token')`

### Additional contract requirements

- `geodes` and `geodes_s3` must be configured under two distinct provider keys (instead of both being defined as `geodes`), so that the public `geodes` provider no longer requires the AWS credentials `aws_access_key_id`, `aws_secret_access_key` and `aws_session_token`.
- The `geodes_s3` provider must be available and expose the sortable fields `id`, `startTimeFromAscendingNode`, `completionTimeFromAscendingNode`, `platformSerialIdentifier` and `cloudCover`, with no maximum number of sort parameters.
- The `geodes_s3` provider must support the same product types as `geodes`, including `S1_SAR_GRD`, `S1_SAR_OCN`, `S1_SAR_SLC`, `S2_MSI_L1C` and `S2_MSI_L2A_MAJA`.
