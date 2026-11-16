[BUG] Error hooks only run if the provider throws
See the issue reported for JS SDK [^1]

Similarly, we need to check details for error and execute error hook in Java SDK [^2]

[^1]: - https://github.com/open-feature/js-sdk/issues/925
[^2]: - https://github.com/open-feature/java-sdk/blob/v1.8.0/src/main/java/dev/openfeature/sdk/OpenFeatureClient.java#L126-L141
