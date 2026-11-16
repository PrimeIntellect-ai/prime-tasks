google cloud storage: NPE from BlobId.java:119
#### Environment details

1. google cloud storage
2. OS type and version: Ubuntu 18.04.4, running in docker container on k8s.
3. Java version:
java version "1.8.0_241"
Java(TM) SE Runtime Environment (build 1.8.0_241-b07)
Java HotSpot(TM) 64-Bit Server VM (build 25.241-b07, mixed mode)
4. storage version(s):
google-cloud-storage-1.113.9.jar
google-cloud-core-1.94.0.jar
google-cloud-core-http-1.94.0.jar

#### Steps to reproduce

  1. Upload content per code below

#### Code example

```java
    BlobId blobId = BlobId.of(bucketName, key);
    String md5;
    try (InputStream inputStream = getInputStream()) {
      md5 = Base64.encodeBase64String(DigestUtils.md5(inputStream));
    }
    BlobInfo blobInfo = BlobInfo.newBuilder(blobId).setContentType(getContentType())
      .setContentDisposition(String.format("attachment; filename=%s", getDownloadName()))
      .setMd5(md5)
      .build();
    storage.createFrom(blobInfo, getInputStream(), Storage.BlobWriteOption.md5Match());
```

#### Stack trace
```
Caused by: java.lang.NullPointerException
    at com.google.cloud.storage.BlobId.fromPb(BlobId.java:119)
    at com.google.cloud.storage.BlobInfo.fromPb(BlobInfo.java:1160)
    at com.google.cloud.storage.Blob.fromPb(Blob.java:958)
    at com.google.cloud.storage.StorageImpl.createFrom(StorageImpl.java:267)
    at com.google.cloud.storage.StorageImpl.createFrom(StorageImpl.java:253)
    at org.ambraproject.rhino.service.impl.GCSObjectStorageServiceImpl.storeFile(GCSObjectStorageServiceImpl.java:72)
    at org.ambraproject.rhino.service.impl.GCSObjectStorageServiceImpl.lambda$null$0(GCSObjectStorageServiceImpl.java:78)
    at java.util.concurrent.FutureTask.run(FutureTask.java:266)
    at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
    at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
```

This is an intermittent issue - I’ve only seen it once, as far as I know. I can’t see how the NPE could be coming from our code. I can’t seem to find any similar issue in the issues list or online.

Thanks for any help you can provide!

### Additional contract requirements

If a transient interruption occurs during the demonstrated upload, the operation may recover and return the created blob, or report a storage failure. It must not surface a `NullPointerException` while decoding the upload response.
