FastJSON2 throws OutOfMemoryError for size limits causing thread termination in async contexts
### Please describe your need or improvement suggestion

FastJSON2 throws an `OutOfMemoryError` when serializing objects exceeding the default size limit (64MB), instead of throwing a more appropriate Runtime exception. This behavior causes serious problems in applications using asynchronous threads, as `Error` instances abruptly terminate threads without any recovery possibility.

In our application, this has caused the thread from Logback to terminate unexpectedly, resulting in our application silently stopping log transmission without any recovery mechanism or warning.

#### Reproduction steps

```java
Map<String, Object> largeMap = new HashMap<>();

// Create a large string (about 1MB)
StringBuilder largeString = new StringBuilder(1024 * 1024);
for (int i = 0; i < 1024 * 1024; i++) {
    largeString.append('a');
}
String baseValue = largeString.toString();

// Create a nested structure exceeding the 64MB limit
for (int i = 0; i < 70; i++) {
    Map<String, Object> nestedMap = new HashMap<>();
    for (int j = 0; j < 10; j++) {
        nestedMap.put("value" + j, baseValue);
    }
    largeMap.put("entry" + i, nestedMap);
}

// This throws OutOfMemoryError
JSON.toJSONString(largeMap);
```

#### Stack trace

```
Exception in thread "AsyncAppender-Worker" java.lang.OutOfMemoryError: try enabling LargeObject feature instead
at com.alibaba.fastjson2.JSONWriter.newCapacity(JSONWriter.java:2701)
at com.alibaba.fastjson2.JSONWriterUTF16.grow0(JSONWriterUTF16.java:1739)
at com.alibaba.fastjson2.JSONWriterUTF16.grow(JSONWriterUTF16.java:1734)
at com.alibaba.fastjson2.JSONWriterUTF16.writeStringLatin1(JSONWriterUTF16.java:307)
...
```

### Please describe the solution you suggest

[HIDDEN]

This solution would allow:
1. Providing meaningful feedback
2. Represents programming errors that could be prevented (like accessing an array beyond its bounds)

### Additional information

This issue is particularly serious in contexts like asynchronous logging frameworks (such as Logback with AsyncAppender), where an error in the processing thread causes a silent failure of the entire logging infrastructure.

The current error message is helpful because it suggests the solution (enabling LargeObject), but the error type chosen is not appropriate for a configurable library limitation.

Related with #966

### Additional contract requirements

- Add a public runtime exception type `com.alibaba.fastjson2.JSONLargeObjectException` with a public constructor `JSONLargeObjectException(String message)` that creates an instance whose message is exactly the supplied message.
- When serialization fails because the requested size exceeds the maximum allowed array size, the thrown `JSONLargeObjectException` message must start with `Maximum array size exceeded. Try enabling LargeObject feature instead. Requested size: `.
