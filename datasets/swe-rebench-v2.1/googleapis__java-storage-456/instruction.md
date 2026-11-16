Expose timeStorageClassUpdated property of the blob's
Add support of `timeStorageClassUpdated ` property of the [blob's](https://github.com/googleapis/google-api-java-client-services/blob/b39bb16a44aa99647d56b39054817ee6493ef8f5/clients/google-api-services-storage/v1/1.30.1/com/google/api/services/storage/model/StorageObject.java#L273). The purpose of exposing these field's is to get the time at which the object's storage class was last changed.

see the api doc : https://cloud.google.com/storage/docs/json_api/v1/objects#resource

~//cc: @frankyn

### Additional contract requirements

- Add a public method `setTimeStorageClassUpdated(Long timeStorageClassUpdated)` to `com.google.cloud.storage.BlobInfo.Builder` that records the epoch-millisecond timestamp at which the object's storage class was last changed and returns the builder for method chaining.
- Add a public method `getTimeStorageClassUpdated()` to `com.google.cloud.storage.BlobInfo` that returns the stored timestamp as a `Long`, or `null` when it has not been set.
- Add a public method `setTimeStorageClassUpdated(Long timeStorageClassUpdated)` to `com.google.cloud.storage.Blob.Builder` that records the timestamp and returns the builder for method chaining.
- Add a public method `getTimeStorageClassUpdated()` to `com.google.cloud.storage.Blob` that returns the remote blob's timestamp as a `Long`, or `null` when it has not been set.
- When a timestamp is present in a Storage API object, a `BlobInfo` or remotely retrieved `Blob` made from that object exposes that timestamp to callers.
- When a timestamp is stored in a `BlobInfo` or `Blob`, it is included in the corresponding Storage API object representation.
