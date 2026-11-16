GCP001 & GCP002 Checks are not applicable
## GCP001 & GCP002 Checks are not applicable
 I've looked at these two rules and believe they may not be relevant checks in their current form. Based on the documentation and some testing, google automatically encrypts disks and buckets if no client-managed encryption is specified.

In some general documentation it is stated [buckets](https://cloud.google.com/storage/docs/encryption) and [disks](https://cloud.google.com/compute/docs/disks/customer-supplied-encryption) are encrypted by default. The options both checks are looking for are used to define customer managed encryption keys.

For disks if you do create the `disk_encryption_key` block and leave it blank, it will [automatically generate keys](https://github.com/terraform-providers/terraform-provider-google/blob/5dfc9b8b72090b9a7c36cb80ad0394b2db43e108/google/resource_compute_disk.go#L274). Buckets are similar in that if you do not specify any encryption it defaults to google managed keys.

### Possible actions
Not sure if deleting a rule is the best course of action. One possibility could be modifying these to warn in the event someone is specifying customer managed keys. ie: remind them to ensure they are securely managing their keys, or to check that the specified `default_kms_key_name` is accessible where the object is being created.

### Additional contract requirements

- The reworked GCP001 check (`GoogleUnencryptedDisk`) reports a `google_compute_disk` resource that does not declare a `disk_encryption_key` block. Such a disk relies on a Google-managed (auto-generated) key rather than a customer-managed key, and the check warns that the disk relies on Google's auto-generated key rather than a customer-managed key. The check does not report a disk that declares a `disk_encryption_key` block containing a `raw_key` or `kms_key_self_link`.
- The new GCP013 check (`GCPRawEncryptionKeySpecifiedForComputeDisk`) reports a `google_compute_disk` resource whose `disk_encryption_key` block specifies a `raw_key`.
- GCP013 does not report a disk whose `disk_encryption_key` block specifies only `kms_key_self_link` and no `raw_key`.
