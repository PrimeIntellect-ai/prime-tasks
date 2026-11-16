Blob.downloadTo() methods do not wrap RetryHelper$RetryHelperException
Quoting source code for one of downloadTo methods:
```
  /**
   * Downloads this blob to the given file path using specified blob read options.
   *
   * @param path destination
   * @param options blob read options
   * @throws StorageException upon failure
   */
  public void downloadTo(Path path, BlobSourceOption... options) {
```
However `StorageException` is never throwing, but confusing `RetryHelper$RetryHelperException` is throwing instead:
```
        String bucketName = "my-bucket";
        String blobName = "my.txt";
        BlobInfo blobInfo = BlobInfo.newBuilder(bucketName, blobName).build();
        String key = "JVzfVl8NLD9FjedFuStegjRfES5ll5zc59CIXw572OA=";

        Blob blob1 = storage.create(blobInfo, Storage.BlobTargetOption.encryptionKey(key));
        blob1.writer().write(ByteBuffer.wrap("Hello".getBytes("UTF8")));

        Blob blob2 = storage.get(blobInfo.getBlobId());
        Path tempFileTo = Files.createTempFile("my_", ".tmp");
        try {
            blob2.downloadTo(tempFileTo);
        } catch (StorageException e) {
            // nice handling
        }
```
Output:
```
Exception in thread "main" com.google.cloud.RetryHelper$RetryHelperException: com.google.cloud.storage.StorageException: 400 Bad Request
The target object is encrypted by a customer-supplied encryption key.
    at com.google.cloud.RetryHelper.runWithRetries(RetryHelper.java:54)
    at com.google.cloud.storage.Blob.downloadTo(Blob.java:236)
    at com.google.cloud.storage.Blob.downloadTo(Blob.java:220)
    at com.google.cloud.storage.Blob.downloadTo(Blob.java:263)
   ...
```

### Additional contract requirements

- When a download performed by any `Blob.downloadTo` overload fails, the caller must receive a `StorageException`, never a `RetryHelper$RetryHelperException`.
