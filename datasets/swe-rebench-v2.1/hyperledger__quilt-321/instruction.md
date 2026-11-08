Make StreamConnection Closeable
Consider making `StreamConnection` auto closeable in a try-with-resources statement by having it implement [Closeable](https://docs.oracle.com/javase/8/docs/api/java/io/Closeable.html).
