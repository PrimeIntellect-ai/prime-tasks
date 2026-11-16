[Feature] display a bucket name in messages when delete objects API returns errors

### Additional contract requirements

- For the tested delete-objects error (bucket `test`, Code `Code`, Key `Key`, VersionId `VersionId`, and Message `Message`), the returned error message must be exactly `DeleteObjectsError: followings\n\nBucketName: test\nCode: Code\nKey: Key\nVersionId: VersionId\nMessage: Message\n`.
