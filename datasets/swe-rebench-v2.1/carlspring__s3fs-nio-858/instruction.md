Properties are not passed down to the S3FileSystem
# Bug Description


```
Map<String, ?> inputProps = Map.of(MAX_CONNECTIONS, "1000", REGION, "eu-west-1")
S3FileSystem = (S3FileSystem) FileSystems.newFileSystem(URI.create("s3://mirror1.amazon.test/"), inputProps)
Properties outputProps = s3fs1.getProperties();
assertThat(outputProps).containsAllEntriesOf(inputProps);
```


# Environment

* `s3fs-nio` version: >= 1.0.0 && <= 1.0.5

# Task Relationships

This bug:
* Is caused by:  #711
