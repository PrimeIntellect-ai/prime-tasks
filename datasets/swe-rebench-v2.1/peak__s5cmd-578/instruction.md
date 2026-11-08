Error in `sync` command when using `--delete` flag with 2.1.0 release
Hi 👋

Firstly I want to thank you for this great tool!

After updating from `2.1.0-beta.1` to `2.1.0` we've encountered a strange behavior when `sync`ing a local folder to our S3 buckets. We're not using AWS, but I could reproduce this issue with a LocalStack S3 bucket locally.

Using s5cmd in version `2.1.0-beta.1` syncs a local folder without any issues:
```
❯ ls -l
total 0
-rw-r--r--  1 x  staff  0 21 Jun 07:47 Test1.txt
-rw-r--r--  1 x  staff  0 21 Jun 07:47 Test2.txt
❯ s5cmd-2.1.0-beta version
v2.1.0-beta.1-3e08061
❯ s5cmd-2.1.0-beta ls s3://test-bucket/\*
ERROR "ls s3://test-bucket/*": no object found
❯ s5cmd-2.1.0-beta --stat --log debug sync --delete ./ s3://test-bucket/
cp Test2.txt s3://test-bucket/Test2.txt
cp Test1.txt s3://test-bucket/Test1.txt

Operation	Total	Error	Success
sync		1	0	1
cp		2	0	2

❯ s5cmd-2.1.0-beta ls s3://test-bucket/\*
2023/06/21 05:54:06                 0 Test1.txt
2023/06/21 05:54:06                 0 Test2.txt
❯ s5cmd-2.1.0-beta --stat --log debug sync --delete ./ s3://test-bucket/
DEBUG "sync Test1.txt s3://test-bucket/Test1.txt": object is newer or same age and object size matches
DEBUG "sync Test2.txt s3://test-bucket/Test2.txt": object is newer or same age and object size matches

Operation	Total	Error	Success
sync		1	0	1
```

Running the exact same commands with s5cmd in version `2.1.0` results in errors (`ERROR "rm --raw=true": expected at least 1 object to remove`) when using the `--delete` flag with the `sync` command:
```
❯ ls -l
total 0
-rw-r--r--  1 x  staff  0 21 Jun 07:47 Test1.txt
-rw-r--r--  1 x  staff  0 21 Jun 07:47 Test2.txt
❯ s5cmd version
v2.1.0-3efbbe8
❯ s5cmd ls s3://test-bucket/\*
ERROR "ls s3://test-bucket/*": no object found
❯ s5cmd --stat --log debug sync --delete ./ s3://test-bucket/
ERROR "rm --raw=true": expected at least 1 object to remove
cp Test2.txt s3://test-bucket/Test2.txt
cp Test1.txt s3://test-bucket/Test1.txt

Operation	Total	Error	Success
cp		2	0	2
sync		1	1	0

❯ s5cmd ls s3://test-bucket/\*
2023/06/21 05:49:47                 0  Test1.txt
2023/06/21 05:49:47                 0  Test2.txt
❯ s5cmd --stat --log debug sync --delete ./ s3://test-bucket/
DEBUG "sync Test1.txt s3://test-bucket/Test1.txt": object is newer or same age and object size matches
DEBUG "sync Test2.txt s3://test-bucket/Test2.txt": object is newer or same age and object size matches
ERROR "rm --raw=true": expected at least 1 object to remove

Operation	Total	Error	Success
sync		1	1	0
```

Is there something we need to change in CLI usage after updating to version `2.1.0`? I don't see any changes regarding the `sync` command and `--delete` flag in the release notes. As the `sync` command is now failing we cannot update s5cmd in our CI/CD pipelines.

If you need anything further, feel free to let me know.

Thank you!

### Additional contract requirements

When `sync --delete` is repeated after the source objects are already present and match at the destination, the run must succeed even when there are no destination-only objects to remove. The source objects must remain available, and matching destination objects must not be deleted.
