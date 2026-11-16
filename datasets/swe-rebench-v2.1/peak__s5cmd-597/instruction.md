[BUG] Sync Continues, Despite Failure to List S3 Bucket
Hello!

First, I'd like to say thank you for providing an amazing tool, `s5cmd` has been invaluable for a migration project I'm doing at $work; I have achieved amazing performance improvements over standard `aws s3 sync` on a very large bucket.

On Friday I hit a very interesting edge case and would like to open a bug report, I have a PR ready which I'll link to the issue which I think will fix it.

**Description:**

Last week when running `s5cmd sync` I messed up the permissions on the target bucket such that it was possible to write objects but not actually list the bucket. Rather than failing the sync simply continued assuming target bucket was empty. This led to a full sync of 250TiB of data from source to destination, as I have versioning enabled on target bucket these copied objects were treated as additional versions and I had a scary spike in my costs as my target bucket went from 250TiB to 500TiB... ouch!

**Steps to reproduce:**

- (Using latest release `v2.1.0-beta.1`)
- Create 2 S3 buckets, grant principal `s3:GetObject, s3:ListBucket` on source bucket and `s3:PutObject, s3:DeleteObject` on destination bucket.
- Run sync command 2 times in a row e.g. `s5cmd sync s3://<source>/* s3://<destination>/`
- Observe that the entire contents are copied both times, with no suggestion there was any issue.

**Expected result:**

The `s5cmd sync` should exit with failure and provide an error message, without ability to successfully list source and destination buckets it's not possible to meet the behaviour of the sync command as provided in the documentation. In addition by not "failing fast" in the sync stage it can lead to an explosion of errors in the cp stage, if for instance you sync to a target bucket that doesn't exist, rather than failing during sync, you'll just get per-object failures as each cp fails with target bucket doesn't exist.

**Actual result:**

`s5cmd sync` runs and exits with success after failing to list target bucket, the target bucket is treated as empty irrespective of the actual contents.

### Additional contract requirements

- If listing either the source or destination bucket fails because access is denied, sync must fail rather than treating the failed listing as an empty bucket.
- A missing destination bucket must be rejected during sync instead of proceeding to per-object copy failures.
- When the destination bucket does not exist, the error output must include `status code: 404`.
