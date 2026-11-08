NPE during upload with 1.113.12
com.google.cloud:libraries-bom:19.0.0 (com.google.cloud:google-cloud-storage:jar:1.113.12), we sometimes see:

```
com.google.cloud.storage.StorageException: java.lang.NullPointerException
	at com.google.cloud.storage.StorageException.translateAndThrow(StorageException.java:81)
	at com.google.cloud.storage.BlobWriteChannel.flushBuffer(BlobWriteChannel.java:209)
	at com.google.cloud.BaseWriteChannel.close(BaseWriteChannel.java:151)
	at com.google.cloud.storage.StorageImpl.createFrom(StorageImpl.java:265)
    ...snip...
Caused by: java.lang.NullPointerException: null
	at com.google.cloud.storage.spi.v1.StorageRpc$Option.get(StorageRpc.java:85)
	at com.google.cloud.storage.spi.v1.StorageRpc$Option.getString(StorageRpc.java:89)
	at com.google.cloud.storage.spi.v1.HttpStorageRpc.setEncryptionHeaders(HttpStorageRpc.java:242)
	at com.google.cloud.storage.spi.v1.HttpStorageRpc.getCall(HttpStorageRpc.java:439)
	at com.google.cloud.storage.spi.v1.HttpStorageRpc.get(HttpStorageRpc.java:455)
	at com.google.cloud.storage.BlobWriteChannel.getRemoteStorageObject(BlobWriteChannel.java:80)
	at com.google.cloud.storage.BlobWriteChannel.access$500(BlobWriteChannel.java:33)
	at com.google.cloud.storage.BlobWriteChannel$1.run(BlobWriteChannel.java:174)
	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
	at com.google.api.gax.retrying.DirectRetryingExecutor.submit(DirectRetryingExecutor.java:105)
	at com.google.cloud.RetryHelper.run(RetryHelper.java:76)
	at com.google.cloud.RetryHelper.runWithRetries(RetryHelper.java:50)
	at com.google.cloud.storage.BlobWriteChannel.flushBuffer(BlobWriteChannel.java:154)
	... 31 common frames omitted
```

Same call succeeds when retried.
