Expose updateTime field of the bucket's
Expose `updateTime `field of the [bucket's](https://github.com/googleapis/google-api-java-client-services/blob/b39bb16a44aa99647d56b39054817ee6493ef8f5/clients/google-api-services-storage/v1/1.30.1/com/google/api/services/storage/model/Bucket.java#L226) it's look like missing here, [see](https://github.com/googleapis/java-storage/blob/master/google-cloud-storage/src/main/java/com/google/cloud/storage/BucketInfo.java#L75-L101).

~//cc: @frankyn

### Additional contract requirements

Expose the bucket metadata update-time value through a public `getUpdateTime()` accessor. The value must be retained when bucket metadata is converted to and from the service representation.
