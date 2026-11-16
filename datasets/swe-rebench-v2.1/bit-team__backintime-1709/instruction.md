Remove dead code related to "filesystem_mounts" and "snapshot_version" field in backup "info" file
https://github.com/bit-team/backintime/blob/d33f35e10b4c3027b3b12881152c157eb1b2cc8c/common/snapshots.py#L1140

The field "filesystem_mounts" (and also "snapshot_version") is written into the "info" file of each backup. It is never used anywhere (checked via grep).

 - Remove that field.
 - Remove `tools.filesystemMountInfo()` because it is used only once at this location.
 - Remove the related unit tests.

My assumption is that this was once added for debug reasons.

**EDIT**: The same goes for the field "snapshot_version". Never used anywhere.
